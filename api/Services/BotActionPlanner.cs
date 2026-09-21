using CroApp.Api.Data;

namespace CroApp.Api.Services;

// One entry per cro currently sitting unread at the bot's own nest - BirdId is the cro being
// replied to, NestFromId is where a reply would need to depart to (see BotOrchestratorService,
// which resolves it the same way a human reply would - back to wherever the inbound cro
// departed from).
public record BotTickInboxItem(string BirdId, string SenderUserId, string SenderUsername, string? Content, string NestFromId);

public record BotTickContact(string UserId, string Username);

public record BotTickHub(string HubId, string Name);

// The world as one bot currently sees it, built fresh by BotOrchestratorService every tick.
public record BotTickContext(
    string BotUserId,
    string BotUsername,
    string Persona,
    string Model,
    List<BotTickInboxItem> Inbox,
    List<BotTickContact> HumanFriends,
    List<BotTickContact> BotFriends,
    List<BotTickHub> Hubs,
    Dictionary<string, int> ConsecutiveBotReplies,
    int MaxConsecutiveBotReplies,
    int MaxContentLength);

// InboundContent is only set for a reply (the text being answered); TargetLabel is a
// human-readable name (friend username / Hub name) used only to steer the LLM's wording.
public record BotPlan(string Action, string TargetId, string TargetLabel, bool IsPublic, string? InboundContent = null);

// Decides what a bot does this tick, with no LLM involved - the dice roll and the weighted
// pick live here so a "do nothing" tick costs zero tokens. Pure (Random injected) so it's
// unit-testable without the emulator.
public static class BotActionPlanner
{
    // True when `senderUserId` is a bot friend this bot has already volleyed with
    // MaxConsecutiveBotReplies times in a row (see BotProfile.ConsecutiveBotReplies).
    public static bool IsCappedBot(BotTickContext context, string senderUserId) =>
        context.BotFriends.Any(b => b.UserId == senderUserId)
        && context.ConsecutiveBotReplies.GetValueOrDefault(senderUserId) >= context.MaxConsecutiveBotReplies;

    // Replies always win and skip the dice: someone is waiting on an answer. Otherwise roll
    // ActChance, then pick among whichever actions currently have a valid target, weighted.
    public static BotPlan? Plan(BotTickContext context, BotOrchestratorOptions options, Random rng)
    {
        var reply = context.Inbox.FirstOrDefault(i => !IsCappedBot(context, i.SenderUserId));
        if (reply is not null)
        {
            return new BotPlan(BotActionKind.ReplyToInbox, reply.BirdId, reply.SenderUsername, false, reply.Content);
        }

        if (rng.NextDouble() >= options.ActChance)
        {
            return null;
        }

        var choices = new List<(int Weight, BotPlan Plan)>();
        if (context.HumanFriends.Count > 0)
        {
            var friend = context.HumanFriends[rng.Next(context.HumanFriends.Count)];
            choices.Add((options.FriendWeight, new BotPlan(BotActionKind.NewToUser, friend.UserId, friend.Username, false)));
            choices.Add((options.PublicWeight, new BotPlan(BotActionKind.NewToUser, friend.UserId, friend.Username, true)));
        }

        var openBots = context.BotFriends.Where(b => !IsCappedBot(context, b.UserId)).ToList();
        if (openBots.Count > 0)
        {
            var bot = openBots[rng.Next(openBots.Count)];
            choices.Add((options.BotWeight, new BotPlan(BotActionKind.NewToBot, bot.UserId, bot.Username, false)));
        }

        if (context.Hubs.Count > 0)
        {
            var hub = context.Hubs[rng.Next(context.Hubs.Count)];
            choices.Add((options.HubWeight, new BotPlan(BotActionKind.NewToHub, hub.HubId, hub.Name, true)));
        }

        var total = choices.Sum(c => Math.Max(c.Weight, 0));
        if (total <= 0)
        {
            return null;
        }

        var roll = rng.Next(total);
        foreach (var (weight, plan) in choices)
        {
            roll -= Math.Max(weight, 0);
            if (roll < 0) return plan;
        }
        return null;
    }
}
