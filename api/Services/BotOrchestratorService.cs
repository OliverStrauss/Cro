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
// and, for any bot whose own per-bot cooldown has elapsed, builds a BotTickContext, asks
// BotDecisionService for one action, and executes it through the exact same BirdService
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
        var decisionService = services.GetRequiredService<BotDecisionService>();

        var bot = await userRepository.GetByIdAsync(profile.UserId);
        if (bot is null || !bot.IsBot)
        {
            logger.LogWarning("BOT_TICK bot={UserId} outcome=Skipped reason=no matching bot User for this BotProfile", profile.UserId);
            return false;
        }

        // A bot only ever acts from its own home nest - it doesn't chase down birds it
        // previously sent elsewhere and left idle at a friend's nest or a Hub. Simple and
        // matches how the inbox it's reacting to always arrives there too.
        var homeNest = (await waypointRepository.ListByUserIdAsync(bot.Id)).FirstOrDefault(w => !w.IsPublic);
        if (homeNest is null)
        {
            logger.LogWarning("BOT_TICK bot={Bot} outcome=Skipped reason=no private home nest", bot.Username);
            return false;
        }

        var residents = await birdService.GetNestResidentsAsync(bot.Id, homeNest.Id);
        var idleOwnBirds = residents.Where(b => b.UserId == bot.Id && !b.IsTraveling).ToList();
        var inboundUnread = residents.Where(b => b.UserId != bot.Id && !b.IsRead).ToList();

        var inbox = new List<BotTickInboxItem>();
        foreach (var bird in inboundUnread)
        {
            var sender = await userRepository.GetByIdAsync(bird.UserId);
            if (sender is null || bird.NestFromId is null) continue;
            inbox.Add(new BotTickInboxItem(bird.Id, sender.Id, sender.Username, bird.Content, bird.NestFromId));
        }

        var humanFriends = new List<BotTickContact>();
        var botFriends = new List<BotTickContact>();
        foreach (var entry in (bot.Friends ?? []).Where(f => f.Status == FriendStatus.Accepted))
        {
            var friend = await userRepository.GetByIdAsync(entry.Id);
            if (friend is null) continue;
            (friend.IsBot ? botFriends : humanFriends).Add(new BotTickContact(friend.Id, friend.Username));
        }

        var watchedHubs = new List<BotTickHub>();
        foreach (var hubId in profile.WatchedHubIds)
        {
            var hub = await hubRepository.GetAsync(hubId);
            if (hub is not null)
            {
                watchedHubs.Add(new BotTickHub(hub.Id, hub.Name));
            }
        }

        var context = new BotTickContext(
            bot.Id,
            bot.Username,
            profile.Persona,
            profile.Model,
            inbox,
            humanFriends,
            botFriends,
            watchedHubs,
            profile.ConsecutiveBotReplies,
            options.Value.MaxConsecutiveBotReplies,
            options.Value.MaxReplyContentLength);

        var decision = await decisionService.DecideAsync(context, cancellationToken);
        var tickedProfile = profile with { LastTickAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };

        if (decision.Action == BotActionKind.None)
        {
            // Also what a failed/unparseable LLM call falls back to - BotDecisionService
            // logs that as its own warning just above this line.
            logger.LogInformation("BOT_TICK bot={Bot} outcome=NoAction reason=LLM chose None (inbox={Inbox}, humanFriends={HumanFriends}, botFriends={BotFriends}, hubs={Hubs})", bot.Username, inbox.Count, humanFriends.Count, botFriends.Count, watchedHubs.Count);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        // Every send action needs one of the bot's own idle, text-capable birds - a Parrot
        // (audio-only) or Pigeon (image-only) can't carry the LLM's text reply (see
        // BirdPayloadValidator.ValidateAllowed), so those are deliberately excluded rather
        // than sending an empty-payload leg.
        var outgoingBird = idleOwnBirds.FirstOrDefault(b => b.Type == BirdTypeCatalog.Cro)
            ?? idleOwnBirds.FirstOrDefault(b => b.Type == BirdTypeCatalog.Raven);
        if (outgoingBird is null)
        {
            // Nothing free to send with this tick (every bird traveling, or only
            // media-only types idle) - stand down rather than force a mismatched send.
            logger.LogInformation("BOT_TICK bot={Bot} outcome=Skipped action={Action} reason=no idle Cro/Raven to send with", bot.Username, decision.Action);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        var replyTarget = decision.Action == BotActionKind.ReplyToInbox
            ? inbox.FirstOrDefault(i => i.BirdId == decision.TargetId)
            : null;

        var destinationNestId = decision.Action switch
        {
            BotActionKind.ReplyToInbox => replyTarget?.NestFromId,
            BotActionKind.NewToUser or BotActionKind.NewToBot =>
                (await waypointRepository.ListByUserIdAsync(decision.TargetId!)).FirstOrDefault(w => !w.IsPublic)?.Id,
            BotActionKind.NewToHub => decision.TargetId,
            _ => null,
        };
        if (destinationNestId is null)
        {
            logger.LogInformation("BOT_TICK bot={Bot} outcome=Skipped action={Action} target={Target} reason=destination nest not found", bot.Username, decision.Action, decision.TargetId);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        // Which bot (if any) this turn's action is aimed at - used only to update the
        // consecutive-bot-reply tally below, never to change what gets sent.
        var botTargetUserId = decision.Action switch
        {
            BotActionKind.NewToBot => decision.TargetId,
            BotActionKind.ReplyToInbox when replyTarget is not null && botFriends.Any(f => f.UserId == replyTarget.SenderUserId) => replyTarget.SenderUserId,
            _ => null,
        };

        try
        {
            await birdService.SendAsync(bot.Id, outgoingBird.Id, destinationNestId, decision.Content, isPublic: false, null, null, 0);
            if (decision.Action == BotActionKind.ReplyToInbox)
            {
                await birdService.MarkReadAsync(bot.Id, decision.TargetId!);
            }
        }
        catch (ServiceException ex)
        {
            // The world moved between context-build and here (destination nest deleted, the
            // chosen bird started traveling from a concurrent tick, etc.) - log and skip this
            // turn, same best-effort posture as every other secondary write in this codebase.
            logger.LogWarning(ex, "BOT_TICK bot={Bot} outcome=Failed action={Action} target={Target} reason={Message}", bot.Username, decision.Action, decision.TargetId, ex.Message);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return false;
        }

        logger.LogInformation("BOT_TICK bot={Bot} outcome=Sent action={Action} target={Target} bird={BirdType} chars={Chars}", bot.Username, decision.Action, decision.TargetId, outgoingBird.Type, decision.Content?.Length ?? 0);

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

        await botProfileRepository.UpdateAsync(tickedProfile with { ConsecutiveBotReplies = consecutiveBotReplies });
        return true;
    }
}
