using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace CroApp.Api.Services;

// One entry per cro currently sitting unread at the bot's own nest - BirdId is what
// BotDecisionService's "ReplyToInbox" targetId must match, NestFromId is where a reply would
// need to depart to (see BotOrchestratorService, which resolves it the same way a human
// reply would - back to wherever the inbound cro departed from).
public record BotTickInboxItem(string BirdId, string SenderUserId, string SenderUsername, string? Content, string NestFromId);

public record BotTickContact(string UserId, string Username);

public record BotTickHub(string HubId, string Name);

// Everything BotDecisionService needs to both build the LLM prompt and validate whatever
// comes back - the "world as this bot currently sees it" for one tick. Built fresh by
// BotOrchestratorService every tick rather than cached; nothing here is expensive to gather
// at this project's per-bot friend/inbox/hub-watchlist scale.
public record BotTickContext(
    string BotUserId,
    string BotUsername,
    string Persona,
    string Model,
    List<BotTickInboxItem> Inbox,
    List<BotTickContact> HumanFriends,
    List<BotTickContact> BotFriends,
    List<BotTickHub> WatchedHubs,
    Dictionary<string, int> ConsecutiveBotReplies,
    int MaxConsecutiveBotReplies,
    int MaxContentLength);

public record BotDecision(string Action, string? TargetId, string? Content)
{
    public static readonly BotDecision None = new(BotActionKind.None, null, null);
}

// Turns a bot's persona + current-tick context into one of the five BotActionKind options,
// via a single DeepInfra chat completion asked to answer in strict JSON. Never lets a bad or
// creative model response reach BirdService: any transport failure, malformed JSON, unknown
// action, or reference to an id that isn't actually in this tick's context falls back to
// BotDecision.None rather than throwing - a bot skipping a turn is always safe, a bot acting
// on a hallucinated target id is not.
public class BotDecisionService(DeepInfraChatClient chatClient, ILogger<BotDecisionService> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<BotDecision> DecideAsync(BotTickContext context, CancellationToken cancellationToken)
    {
        string? raw;
        try
        {
            raw = await chatClient.CompleteJsonAsync(context.Model, BuildSystemPrompt(context), BuildUserPrompt(context), cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "DeepInfra call failed for bot {BotUserId}; defaulting to no action.", context.BotUserId);
            return BotDecision.None;
        }

        var decision = ParseAndValidate(raw, context);
        if (decision.Action != BotActionKind.None)
        {
            logger.LogInformation("Bot {BotUserId} decided {Action} -> {TargetId}", context.BotUserId, decision.Action, decision.TargetId);
        }
        return decision;
    }

    private static string BuildSystemPrompt(BotTickContext context) =>
        $"""
        You are {context.BotUsername}, a character living inside Cro, a messaging app where
        every message ("cro") physically travels across a map and takes real time to arrive -
        there is no instant chat here. Your personality: {context.Persona}

        Stay fully in character. Any message you write should be short (1-3 sentences), like
        a real chat message - not an email, not a narration of your own actions.

        On each turn, choose exactly one action and respond with ONLY a JSON object, no other
        text, in this shape:
        {{"action": "<one of: None, ReplyToInbox, NewToUser, NewToBot, NewToHub>", "targetId": "<id, or null for None>", "content": "<your message, or null for None>"}}

        Action meanings:
        - None: do nothing this turn.
        - ReplyToInbox: reply to one specific unread cro in your inbox. targetId is that cro's id.
        - NewToUser: start a brand-new cro to one of your human friends. targetId is their user id.
        - NewToBot: start a brand-new cro to one of your bot friends. targetId is their user id.
        - NewToHub: post a brand-new cro to one of the Hubs you watch. targetId is the Hub's id.

        Only ever use an id that appears in the lists you're given - never invent one. Most
        turns the right choice is None: a real person doesn't message every few minutes, and
        neither should you.
        """;

    private static string BuildUserPrompt(BotTickContext context)
    {
        var inbox = context.Inbox.Count == 0
            ? "(nothing unread)"
            : string.Join("\n", context.Inbox.Select(i => $"- id={i.BirdId} from {i.SenderUsername} (user id {i.SenderUserId}): \"{i.Content}\""));
        var humans = context.HumanFriends.Count == 0
            ? "(none)"
            : string.Join("\n", context.HumanFriends.Select(f => $"- {f.Username} (user id {f.UserId})"));
        var bots = context.BotFriends.Count == 0
            ? "(none)"
            : string.Join("\n", context.BotFriends.Select(f => $"- {f.Username} (user id {f.UserId})"));
        var hubs = context.WatchedHubs.Count == 0
            ? "(none)"
            : string.Join("\n", context.WatchedHubs.Select(h => $"- {h.Name} (hub id {h.HubId})"));

        return $"""
            Your unread inbox:
            {inbox}

            Your human friends:
            {humans}

            Your bot friends:
            {bots}

            Hubs you watch:
            {hubs}

            Choose your action now.
            """;
    }

    // Public (not private) specifically so it's independently unit-testable without a Cosmos
    // emulator - this is the one piece of bot logic worth testing at the pure-function level,
    // since it's the sole gate between an LLM's raw text and a real BirdService.SendAsync call
    // (see BotDecisionServiceTests).
    public static BotDecision ParseAndValidate(string? raw, BotTickContext context)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return BotDecision.None;
        }

        RawDecision? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<RawDecision>(raw, JsonOptions);
        }
        catch (JsonException)
        {
            return BotDecision.None;
        }

        var action = parsed?.Action?.Trim();
        if (string.IsNullOrEmpty(action) || !BotActionKind.IsValid(action) || action == BotActionKind.None)
        {
            return BotDecision.None;
        }

        var targetId = parsed!.TargetId?.Trim();
        var content = parsed.Content?.Trim();
        if (string.IsNullOrEmpty(targetId) || string.IsNullOrEmpty(content))
        {
            return BotDecision.None;
        }
        if (content.Length > context.MaxContentLength)
        {
            content = content[..context.MaxContentLength];
        }

        var targetExists = action switch
        {
            BotActionKind.ReplyToInbox => context.Inbox.Any(i => i.BirdId == targetId),
            BotActionKind.NewToUser => context.HumanFriends.Any(f => f.UserId == targetId),
            BotActionKind.NewToBot => context.BotFriends.Any(f => f.UserId == targetId),
            BotActionKind.NewToHub => context.WatchedHubs.Any(h => h.HubId == targetId),
            _ => false,
        };
        if (!targetExists)
        {
            return BotDecision.None;
        }

        // Bot-to-bot volley cap (see BotProfile.ConsecutiveBotReplies) - checked here rather
        // than left to the orchestrator so an over-the-cap NewToBot never even counts as a
        // "decision" the caller has to remember to double-check.
        if (action == BotActionKind.NewToBot && context.ConsecutiveBotReplies.GetValueOrDefault(targetId) >= context.MaxConsecutiveBotReplies)
        {
            return BotDecision.None;
        }

        return new BotDecision(action, targetId, content);
    }

    private record RawDecision(string? Action, string? TargetId, string? Content);
}
