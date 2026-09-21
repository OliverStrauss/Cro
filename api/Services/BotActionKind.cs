namespace CroApp.Api.Services;

// What a bot can do on a tick. BotActionPlanner (plain C#, not the LLM) picks one of these
// plus its target; the LLM is only ever asked to write the message text for it. Shooing
// isn't listed - it's a rule-based sweep (see BotOrchestratorService), not a chosen action.
public static class BotActionKind
{
    public const string ReplyToInbox = "ReplyToInbox";
    public const string NewToUser = "NewToUser";
    public const string NewToBot = "NewToBot";
    public const string NewToHub = "NewToHub";
}
