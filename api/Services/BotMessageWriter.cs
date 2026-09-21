using Microsoft.Extensions.Logging;

namespace CroApp.Api.Services;

// Asks the LLM for just the text of a message BotActionPlanner already decided to send -
// no menu, no ids, no JSON, so the prompt and the completion both stay tiny. Any transport
// failure or empty completion returns null and the tick is simply skipped; a bot going
// quiet for a turn is always safe.
public class BotMessageWriter(DeepInfraChatClient chatClient, ILogger<BotMessageWriter> logger)
{
    public async Task<string?> WriteAsync(BotTickContext context, BotPlan plan, CancellationToken cancellationToken)
    {
        try
        {
            var raw = await chatClient.CompleteAsync(context.Model, BuildSystemPrompt(context), BuildUserPrompt(plan), cancellationToken);
            return Clean(raw, context.MaxContentLength);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "DeepInfra call failed for bot {BotUserId}; skipping this turn.", context.BotUserId);
            return null;
        }
    }

    private static string BuildSystemPrompt(BotTickContext context) =>
        $"""
        You are {context.BotUsername}, a character in Cro, a messaging app where every message
        ("cro") physically travels across a map and takes real time to arrive. Your personality:
        {context.Persona}
        Stay fully in character. Reply with ONLY the message text: 1-3 short sentences, like a
        real chat message. No quotes, no narration of your own actions.
        """;

    private static string BuildUserPrompt(BotPlan plan) => plan.Action switch
    {
        BotActionKind.ReplyToInbox => $"{plan.TargetLabel} sent you: \"{plan.InboundContent}\"\nWrite your reply.",
        BotActionKind.NewToHub => $"Write a message to post on the public board of the landmark \"{plan.TargetLabel}\".",
        _ when plan.IsPublic => $"Write a new public message (anyone on the map can read it), sent via your friend {plan.TargetLabel}'s nest.",
        _ => $"Write a new message to your friend {plan.TargetLabel}.",
    };

    // Public for unit testing: strips wrapping quotes the model likes to add, and clips to the
    // configured cap - the one place a runaway completion gets truncated before it reaches a Bird.
    public static string? Clean(string? raw, int maxLength)
    {
        var text = raw?.Trim().Trim('"', '“', '”').Trim();
        if (string.IsNullOrEmpty(text)) return null;
        return text.Length > maxLength ? text[..maxLength] : text;
    }
}
