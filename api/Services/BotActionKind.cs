namespace CroApp.Api.Services;

// The fixed menu BotDecisionService asks the LLM to choose from on every tick, exactly the
// five options the product wants a bot to have: do nothing, reply to something already
// sitting unread in its inbox, or start a fresh cro to a user/bot/Hub. Deliberately closed -
// BotDecisionService.ParseAndValidate rejects anything outside this set (and any malformed
// JSON at all) by falling back to None, so a bad or creative LLM response can never reach
// BirdService with an action it wasn't built to validate.
public static class BotActionKind
{
    public const string None = "None";
    public const string ReplyToInbox = "ReplyToInbox";
    public const string NewToUser = "NewToUser";
    public const string NewToBot = "NewToBot";
    public const string NewToHub = "NewToHub";

    public static readonly string[] All = [None, ReplyToInbox, NewToUser, NewToBot, NewToHub];

    public static bool IsValid(string action) => All.Contains(action);
}
