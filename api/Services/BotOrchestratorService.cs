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

        foreach (var profile in enabled)
        {
            if (cancellationToken.IsCancellationRequested) return;
            if (profile.LastTickAt is not null && now - profile.LastTickAt < cooldown) continue;

            // Each bot gets its own DI scope (not just the sweep as a whole), so one bot's
            // failure can't leave a scoped repository/service in a bad state for the next.
            using var botScope = scopeFactory.CreateScope();
            try
            {
                await TickBotAsync(botScope.ServiceProvider, profile, cancellationToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Tick failed for bot {UserId}; will retry next sweep.", profile.UserId);
            }
        }
    }

    private async Task TickBotAsync(IServiceProvider services, BotProfile profile, CancellationToken cancellationToken)
    {
        var userRepository = services.GetRequiredService<CosmosUserRepository>();
        var waypointRepository = services.GetRequiredService<CosmosWaypointRepository>();
        var hubRepository = services.GetRequiredService<CosmosHubRepository>();
        var botProfileRepository = services.GetRequiredService<CosmosBotProfileRepository>();
        var birdService = services.GetRequiredService<BirdService>();
        var writer = services.GetRequiredService<BotMessageWriter>();

        var bot = await userRepository.GetByIdAsync(profile.UserId);
        if (bot is null || !bot.IsBot)
        {
            logger.LogWarning("BotProfile {UserId} has no matching bot User; skipping.", profile.UserId);
            return;
        }

        // A bot only ever acts from its own home nest - it doesn't chase down birds it
        // previously sent elsewhere and left idle at a friend's nest or a Hub. Simple and
        // matches how the inbox it's reacting to always arrives there too.
        var homeNest = (await waypointRepository.ListByUserIdAsync(bot.Id)).FirstOrDefault(w => !w.IsPublic);
        if (homeNest is null)
        {
            return; // no nest yet to act from
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

        var hubs = (await hubRepository.ListApprovedAsync()).Select(h => new BotTickHub(h.Id, h.Name)).ToList();

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
            await botProfileRepository.UpdateAsync(tickedProfile);
            return;
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
            await botProfileRepository.UpdateAsync(tickedProfile);
            return;
        }

        var replyTarget = plan.Action == BotActionKind.ReplyToInbox
            ? inbox.First(i => i.BirdId == plan.TargetId)
            : null;

        var destinationNestId = plan.Action switch
        {
            BotActionKind.ReplyToInbox => replyTarget!.NestFromId,
            BotActionKind.NewToUser or BotActionKind.NewToBot =>
                (await waypointRepository.ListByUserIdAsync(plan.TargetId)).FirstOrDefault(w => !w.IsPublic)?.Id,
            BotActionKind.NewToHub => plan.TargetId,
            _ => null,
        };
        if (destinationNestId is null)
        {
            await botProfileRepository.UpdateAsync(tickedProfile);
            return;
        }

        var content = await writer.WriteAsync(context, plan, cancellationToken);
        if (content is null)
        {
            await botProfileRepository.UpdateAsync(tickedProfile);
            return;
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
            logger.LogWarning(ex, "Bot {UserId} action {Action} failed: {Message}", bot.Id, plan.Action, ex.Message);
            await botProfileRepository.UpdateAsync(tickedProfile);
            return;
        }

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
    }
}
