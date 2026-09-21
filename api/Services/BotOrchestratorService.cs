using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// The one background loop in this API - before this, nothing here ran on a timer; every
// other delayed effect (Bird arrival, most notably) is lazy-on-read instead (see
// BirdService.ResolveArrivalIfDueAsync). Sweeps every enabled BotProfile on a fixed interval
// and, for any bot whose own per-bot cooldown has elapsed, builds a BotTickContext, lets
// BotActionPlanner pick an action (dice roll, no LLM), has BotMessageWriter write just the
// text, and executes it through the exact same BirdService
// codepath a human player's request would go through - a bot's cro travels at the same real
// travel-time speed as anyone else's (BirdService.SendAsync), there is no bot-only fast path,
// and every arrival still posts to Hub boards / bumps friend exchange counts / fires Events
// completely unmodified.
//
// Only ever registered when DeepInfra:ApiKey is configured (see Program.cs) - an
// unconfigured environment (every test fixture, a fresh checkout) never spins this up at
// all, rather than running a timer that can only ever no-op.
public class BotOrchestratorService(
    IServiceScopeFactory scopeFactory,
    IOptions<BotOrchestratorOptions> options,
    ILogger<BotOrchestratorService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(Math.Max(options.Value.TickIntervalSeconds, 15));
        logger.LogInformation("BOT_ORCHESTRATOR started: sweep every {IntervalSeconds}s, per-bot cooldown {CooldownMinutes}m.", interval.TotalSeconds, Math.Max(options.Value.TickCooldownMinutes, 1));
        using var timer = new PeriodicTimer(interval);
        do
        {
            try
            {
                await RunSweepAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Bot orchestrator sweep failed.");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task RunSweepAsync(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var botProfileRepository = scope.ServiceProvider.GetRequiredService<CosmosBotProfileRepository>();
        var enabled = await botProfileRepository.ListEnabledAsync();
        var cooldown = TimeSpan.FromMinutes(Math.Max(options.Value.TickCooldownMinutes, 1));
        var now = DateTimeOffset.UtcNow;
        var ticked = 0;
        var sent = 0;

        if (enabled.Count == 0)
        {
            logger.LogWarning("BOT_SWEEP no enabled bots found - nothing will ever be sent (was BotSeeder run / is BotProfile.IsEnabled set?).");
        }

        foreach (var profile in enabled)
        {
            if (cancellationToken.IsCancellationRequested) return;
            if (profile.LastTickAt is not null && now - profile.LastTickAt < cooldown) continue;
            ticked++;

            // Each bot gets its own DI scope (not just the sweep as a whole), so one bot's
            // failure can't leave a scoped repository/service in a bad state for the next.
            using var botScope = scopeFactory.CreateScope();
            try
            {
                if (await TickBotAsync(botScope.ServiceProvider, profile, cancellationToken)) sent++;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "BOT_TICK bot={UserId} outcome=Failed reason=exception; will retry next sweep.", profile.UserId);
            }
        }

        // Quiet sweeps (every bot still cooling down) stay at Debug so a 60s timer doesn't
        // write ~1,400 lines a day; any sweep that actually ticked a bot is Information.
        logger.Log(ticked > 0 ? LogLevel.Information : LogLevel.Debug,
            "BOT_SWEEP enabled={Enabled} ticked={Ticked} sent={Sent} cooling_down={CoolingDown}",
            enabled.Count, ticked, sent, enabled.Count - ticked);
    }

    // Returns true iff this tick actually sent a cro. Every exit logs exactly one BOT_TICK line.
    private async Task<bool> TickBotAsync(IServiceProvider services, BotProfile profile, CancellationToken cancellationToken)
    {
        var userRepository = services.GetRequiredService<CosmosUserRepository>();
        var waypointRepository = services.GetRequiredService<CosmosWaypointRepository>();
        var hubRepository = services.GetRequiredService<CosmosHubRepository>();
        var botProfileRepository = services.GetRequiredService<CosmosBotProfileRepository>();
        var birdService = services.GetRequiredService<BirdService>();
        var pinService = services.GetRequiredService<PinService>();
        var writer = services.GetRequiredService<BotMessageWriter>();

        var bot = await userRepository.GetByIdAsync(profile.UserId);
        if (bot is null || !bot.IsBot)
        {
            logger.LogWarning("BOT_TICK bot={UserId} outcome=Skipped reason=no matching bot User for this BotProfile", profile.UserId);
            return false;
        }

        // A bot only ever acts from its own home nest - birds it sent elsewhere are only
        // recalled home (RecallAfterHours below), never sent onward from where they sit.
        var homeNest = (await waypointRepository.ListByUserIdAsync(bot.Id)).FirstOrDefault(w => !w.IsPublic);
        if (homeNest is null)
        {
            logger.LogWarning("BOT_TICK bot={Bot} outcome=Skipped reason=no private home nest", bot.Username);
            return false;
        }

        var residents = await birdService.GetNestResidentsAsync(bot.Id, homeNest.Id);
        var idleOwnBirds = residents.Where(b => b.UserId == bot.Id && !b.IsTraveling).ToList();
        var inboundUnread = residents.Where(b => b.UserId != bot.Id && !b.IsRead).ToList();

        // Rule-based, no LLM: someone else's bird that's been read (i.e. answered or
        // deliberately ignored) and has rested here past ShooAfterHours gets sent home.
        // EstimatedArrivalAt is left in place after landing, so it doubles as the arrival
        // time - UpdatedAt can't, since reading/pinning/renaming a bird bumps it too. Runs on
        // the per-bot cooldown cadence, which is fine for an hours-scale rule.
        var shooCutoff = DateTimeOffset.UtcNow.AddHours(-Math.Max(options.Value.ShooAfterHours, 1));
        foreach (var stale in residents.Where(b => b.UserId != bot.Id && !b.IsTraveling && b.IsRead && b.EstimatedArrivalAt <= shooCutoff))
        {
            try
            {
                await birdService.ShooAsync(bot.Id, stale.Id);
            }
            catch (ServiceException ex)
            {
                logger.LogWarning(ex, "Bot {UserId} failed to shoo bird {BirdId}: {Message}", bot.Id, stale.Id, ex.Message);
            }
        }

        // Rule-based, no LLM: the bot's own bird that's been resting away from home (a friend's
        // nest or a Hub) past RecallAfterHours gets sent back to the home nest - the same resend
        // a human does. Payload-less, like any leg with nothing new to say. Arrival time is
        // EstimatedArrivalAt, same reasoning as the shoo cutoff above.
        var recallCutoff = DateTimeOffset.UtcNow.AddHours(-Math.Max(options.Value.RecallAfterHours, 1));
        var ownBirds = await birdService.ListAsync(bot.Id);
        foreach (var away in ownBirds.Where(b => !b.IsTraveling && b.CurrentNestId is not null && b.CurrentNestId != homeNest.Id && b.EstimatedArrivalAt <= recallCutoff))
        {
            try
            {
                await birdService.SendAsync(bot.Id, away.Id, homeNest.Id, null, false, null, null, 0);
            }
            catch (ServiceException ex)
            {
                logger.LogWarning(ex, "Bot {UserId} failed to recall bird {BirdId}: {Message}", bot.Id, away.Id, ex.Message);
            }
        }

        var inbox = new List<BotTickInboxItem>();
        foreach (var bird in inboundUnread)
        {
            var sender = await userRepository.GetByIdAsync(bird.UserId);
            if (sender is null || bird.NestFromId is null) continue;
            inbox.Add(new BotTickInboxItem(bird.Id, sender.Id, sender.Username, bird.Content, bird.NestFromId));
        }

        // Pin each inbound cro before anything reads or shoos it - a pin is the durable
        // conversation log (a bird's own Content gets overwritten on its next journey).
        // Reading a bird bumps UpdatedAt, which changes the pin id, so this only ever pins
        // still-unread birds and skips one already pinned for its current delivery (a bird the
        // bot couldn't answer this tick would otherwise re-pin, and re-notify its sender, every tick).
        foreach (var item in inbox.Where(_ => Random.Shared.NextDouble() < options.Value.PinChance))
        {
            try
            {
                if (await pinService.GetForCurrentDeliveryAsync(bot.Id, item.BirdId) is null)
                {
                    await pinService.PinAsync(bot.Id, item.BirdId);
                }
            }
            catch (ServiceException ex)
            {
                logger.LogWarning(ex, "Bot {UserId} failed to pin bird {BirdId}: {Message}", bot.Id, item.BirdId, ex.Message);
            }
        }

        var humanFriends = new List<BotTickContact>();
        var botFriends = new List<BotTickContact>();
        foreach (var entry in (bot.Friends ?? []).Where(f => f.Status == FriendStatus.Accepted))
        {
            var friend = await userRepository.GetByIdAsync(entry.Id);
            if (friend is null) continue;
            (friend.IsBot ? botFriends : humanFriends).Add(new BotTickContact(friend.Id, friend.Username));
        }

        var approvedHubs = await hubRepository.ListApprovedAsync();
        var hubs = approvedHubs.Select(h => new BotTickHub(h.Id, h.Name)).ToList();

        var context = new BotTickContext(
            bot.Id,
            bot.Username,
            profile.Persona,
            profile.Model,
            inbox,
            humanFriends,
            botFriends,
            hubs,
            profile.ConsecutiveBotReplies,
            options.Value.MaxConsecutiveBotReplies,
            options.Value.MaxReplyContentLength);

        var tickedProfile = profile with { LastTickAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };

        // A bot-to-bot volley already at its cap is never answered - mark it read instead so
        // it doesn't sit unread forever, and (being read) gets shooed after ShooAfterHours.
        foreach (var capped in inbox.Where(i => BotActionPlanner.IsCappedBot(context, i.SenderUserId)))
        {
            await birdService.MarkReadAsync(bot.Id, capped.BirdId);
        }

        var plan = BotActionPlanner.Plan(context, options.Value, Random.Shared);
        if (plan is null)
        {
            logger.LogInformation("BOT_TICK bot={Bot} outcome=NoAction reason=planner rolled no action (inbox={Inbox}, humanFriends={HumanFriends}, botFriends={BotFriends})", bot.Username, inbox.Count, humanFriends.Count, botFriends.Count);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        // Every send action needs one of the bot's own idle, text-capable birds - a Parrot
        // (audio-only) or Pigeon (image-only) can't carry the LLM's text reply (see
        // BirdPayloadValidator.ValidateAllowed), so those are deliberately excluded rather
        // than sending an empty-payload leg. Checked before the LLM call so a send that can't
        // happen never costs tokens.
        var outgoingBird = idleOwnBirds.FirstOrDefault(b => b.Type == BirdTypeCatalog.Cro)
            ?? idleOwnBirds.FirstOrDefault(b => b.Type == BirdTypeCatalog.Raven);
        if (outgoingBird is null)
        {
            // Nothing free to send with this tick (every bird traveling, or only
            // media-only types idle) - stand down rather than force a mismatched send.
            logger.LogInformation("BOT_TICK bot={Bot} outcome=Skipped action={Action} reason=no idle Cro/Raven to send with", bot.Username, plan.Action);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        var replyTarget = plan.Action == BotActionKind.ReplyToInbox
            ? inbox.First(i => i.BirdId == plan.TargetId)
            : null;

        // Fetched (rather than just its id) so the backdrop can say how far the cro travels. A
        // reply keeps NestFromId as its destination even if this lookup comes back null, so a
        // deleted sender nest still hits the 404 abandon path below instead of skipping here.
        var destinationNest = plan.Action switch
        {
            BotActionKind.ReplyToInbox => await waypointRepository.GetAsync(replyTarget!.SenderUserId, replyTarget.NestFromId),
            BotActionKind.NewToUser or BotActionKind.NewToBot =>
                (await waypointRepository.ListByUserIdAsync(plan.TargetId)).FirstOrDefault(w => !w.IsPublic),
            _ => null,
        };
        var destinationNestId = plan.Action switch
        {
            BotActionKind.ReplyToInbox => replyTarget!.NestFromId,
            BotActionKind.NewToUser or BotActionKind.NewToBot => destinationNest?.Id,
            BotActionKind.NewToHub => plan.TargetId,
            _ => null,
        };
        if (destinationNestId is null)
        {
            logger.LogInformation("BOT_TICK bot={Bot} outcome=Skipped action={Action} target={Target} reason=destination nest not found", bot.Username, plan.Action, plan.TargetId);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        // The friend this action is a conversation with (Hub posts have none) - keys both the
        // remembered thread read below and the one written after a successful send.
        var threadKey = plan.Action switch
        {
            BotActionKind.ReplyToInbox => replyTarget!.SenderUserId,
            BotActionKind.NewToUser or BotActionKind.NewToBot => plan.TargetId,
            _ => null,
        };

        var hub = plan.Action == BotActionKind.NewToHub ? approvedHubs.FirstOrDefault(h => h.Id == plan.TargetId) : null;
        var destLat = destinationNest?.Latitude ?? hub?.Latitude;
        var destLng = destinationNest?.Longitude ?? hub?.Longitude;
        double? km = destLat is { } lat && destLng is { } lng
            ? GeoDistance.HaversineKm(homeNest.Latitude, homeNest.Longitude, lat, lng)
            : null;

        var inboundBird = replyTarget is null ? null : residents.FirstOrDefault(b => b.Id == replyTarget.BirdId);
        TimeSpan? took = inboundBird?.DepartedAt is { } departed && inboundBird.EstimatedArrivalAt is { } arrived ? arrived - departed : null;

        var boardTail = plan.Action == BotActionKind.NewToHub
            ? await BuildBoardTailAsync(services.GetRequiredService<CosmosHubMessageRepository>(), plan.TargetId)
            : [];

        var backdrop = new BotBackdrop(
            BotBackdropFacts.LocalTime(DateTimeOffset.UtcNow, homeNest.Longitude),
            bot.Friends?.FirstOrDefault(f => f.Id == threadKey)?.ExchangeCount ?? 0,
            plan.Action == BotActionKind.ReplyToInbox
                ? BotBackdropFacts.ReplyNote(plan.TargetLabel, km, took)
                : BotBackdropFacts.OutboundNote(plan.TargetLabel, km),
            threadKey is not null && profile.Threads?.GetValueOrDefault(threadKey) is { } remembered ? remembered : [],
            boardTail);

        var content = await writer.WriteAsync(context, plan, backdrop, cancellationToken);
        if (content is null)
        {
            logger.LogInformation("BOT_TICK bot={Bot} outcome=Skipped action={Action} target={Target} reason=LLM produced no message", bot.Username, plan.Action, plan.TargetId);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        // Which bot (if any) this turn's action is aimed at - used only to update the
        // consecutive-bot-reply tally below, never to change what gets sent.
        var botTargetUserId = plan.Action switch
        {
            BotActionKind.NewToBot => plan.TargetId,
            BotActionKind.ReplyToInbox when botFriends.Any(f => f.UserId == replyTarget!.SenderUserId) => replyTarget!.SenderUserId,
            _ => null,
        };

        try
        {
            await birdService.SendAsync(bot.Id, outgoingBird.Id, destinationNestId, content, plan.IsPublic, null, null, 0);
            if (plan.Action == BotActionKind.ReplyToInbox)
            {
                await birdService.MarkReadAsync(bot.Id, plan.TargetId);
            }
        }
        catch (ServiceException ex)
        {
            // The world moved between context-build and here (destination nest deleted, the
            // chosen bird started traveling from a concurrent tick, etc.) - log and skip this
            // turn, same best-effort posture as every other secondary write in this codebase.
            logger.LogWarning(ex, "BOT_TICK bot={Bot} outcome=Failed action={Action} target={Target} reason={Message}", bot.Username, plan.Action, plan.TargetId, ex.Message);
            if (BotActionPlanner.ShouldAbandonReply(plan, ex.StatusCode))
            {
                // The planner always picks a reply first, so an unanswerable one (its sender's
                // nest is gone/unreachable) would be re-picked and re-fail every tick, freezing
                // the bot. Mark it read so the next tick moves on; being read, it's also shooed
                // after ShooAfterHours.
                try
                {
                    await birdService.MarkReadAsync(bot.Id, plan.TargetId);
                    logger.LogWarning("BOT_TICK bot={Bot} abandoned unanswerable reply to bird={Target}, marked read.", bot.Username, plan.TargetId);
                }
                catch (ServiceException markEx)
                {
                    logger.LogWarning(markEx, "Bot {UserId} failed to mark bird {BirdId} read after abandoning its reply: {Message}", bot.Id, plan.TargetId, markEx.Message);
                }
            }
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        logger.LogInformation("BOT_TICK bot={Bot} outcome=Sent action={Action} target={Target} bird={BirdType} chars={Chars}", bot.Username, plan.Action, plan.TargetId, outgoingBird.Type, content.Length);

        var consecutiveBotReplies = new Dictionary<string, int>(profile.ConsecutiveBotReplies);
        if (botTargetUserId is not null)
        {
            consecutiveBotReplies[botTargetUserId] = consecutiveBotReplies.GetValueOrDefault(botTargetUserId) + 1;
        }
        else
        {
            // Talked to (or replied to) a human this turn - drop the whole bot-volley tally,
            // modeling "got distracted by a person" rather than tracking each bot pairing's
            // cooldown independently (see BotProfile.ConsecutiveBotReplies).
            consecutiveBotReplies.Clear();
        }

        // Remember this exchange (what they said, if this was a reply, then what the bot said)
        // so the next message to/from this friend is written with the thread in view.
        var threads = profile.Threads;
        if (threadKey is not null)
        {
            var lines = new List<BotThreadLine>();
            if (replyTarget?.Content is { } inbound) lines.Add(new BotThreadLine(false, inbound));
            lines.Add(new BotThreadLine(true, content));
            threads = new Dictionary<string, List<BotThreadLine>>(profile.Threads ?? [])
            {
                [threadKey] = BotBackdropFacts.AppendThread(profile.Threads?.GetValueOrDefault(threadKey), lines),
            };
        }

        await botProfileRepository.UpdateAsync(tickedProfile with { ConsecutiveBotReplies = consecutiveBotReplies, Threads = threads });
        return true;
    }

    // ponytail: ListByHubIdAsync reads the whole board (7-day TTL, so small) and takes the tail
    // in memory - swap for a TOP query on the repository if boards ever get busy.
    private static async Task<List<string>> BuildBoardTailAsync(CosmosHubMessageRepository hubMessageRepository, string hubId) =>
        (await hubMessageRepository.ListByHubIdAsync(hubId))
            .Where(m => !string.IsNullOrWhiteSpace(m.Content))
            .Take(BotBackdropFacts.BoardTailSize)
            .Reverse()
            .Select(m => $"{m.SenderUsername}: {m.Content}")
            .ToList();
}
