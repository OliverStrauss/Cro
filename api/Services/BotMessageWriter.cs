using System.Text;
using Microsoft.Extensions.Logging;

namespace CroApp.Api.Services;

// Asks the LLM for just the text of a message BotActionPlanner already decided to send -
// no menu, no ids, no JSON, so the prompt and the completion both stay tiny. Any transport
// failure or empty completion returns null and the tick is simply skipped; a bot going
// quiet for a turn is always safe.
public class BotMessageWriter(DeepInfraChatClient chatClient, ILogger<BotMessageWriter> logger)
{
    public async Task<string?> WriteAsync(BotTickContext context, BotPlan plan, BotBackdrop backdrop, CancellationToken cancellationToken)
    {
        try
        {
            var raw = await chatClient.CompleteAsync(context.Model, BuildSystemPrompt(context), BuildUserPrompt(plan, backdrop), cancellationToken);
            return Clean(raw, context.MaxContentLength);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "BOT_LLM call failed for bot {BotUserId}; skipping this turn.", context.BotUserId);
            return null;
        }
    }

    private static string BuildSystemPrompt(BotTickContext context) =>
        $"""
        You are {context.BotUsername}, a character in Cro, a messaging app where every message
        ("cro") physically travels across a map and takes real time to arrive. Your personality:
        {context.Persona}
        Stay fully in character. Reply with ONLY the message text: 1-3 short sentences, like a
        real chat message. No quotes, no narration of your own actions. Let any context below
        color your message naturally - never recite it, and don't repeat what you already said.
        """;

    // Public for unit testing. Context lines come first and the ask last, so the model's final
    // instruction is always the same one-line task it got before backdrops existed.
    public static string BuildUserPrompt(BotPlan plan, BotBackdrop backdrop)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"It's {backdrop.LocalTime} where you live.");
        if (backdrop.ExchangeCount > 0) sb.AppendLine($"You and {plan.TargetLabel} have traded {backdrop.ExchangeCount} cros so far.");
        if (backdrop.TravelNote is not null) sb.AppendLine(backdrop.TravelNote);
        if (backdrop.History.Count > 0)
        {
            sb.AppendLine("Your recent conversation, oldest first:");
            foreach (var line in backdrop.History) sb.AppendLine($"{(line.FromMe ? "You" : plan.TargetLabel)}: {Clip(line.Text)}");
        }
        if (backdrop.BoardTail.Count > 0)
        {
            sb.AppendLine("Latest posts on this board, oldest first:");
            foreach (var post in backdrop.BoardTail) sb.AppendLine(Clip(post));
        }
        sb.Append(plan.Action switch
        {
            BotActionKind.ReplyToInbox => $"{plan.TargetLabel} sent you: \"{plan.InboundContent}\"\nWrite your reply.",
            BotActionKind.NewToHub => $"Write a message to post on the public board of the landmark \"{plan.TargetLabel}\".",
            _ when plan.IsPublic => $"Write a new public message (anyone on the map can read it), sent via your friend {plan.TargetLabel}'s nest.",
            _ => $"Write a new message to your friend {plan.TargetLabel}.",
        });
        return sb.ToString();
    }

    // History/board lines are context, not the message being answered - clipped so six of them
    // can't balloon the prompt (and the per-token bill) on a chatty thread.
    private static string Clip(string text) => text.Length > 200 ? text[..200] + "..." : text;

    // Public for unit testing: strips wrapping quotes the model likes to add, and clips to the
    // configured cap - the one place a runaway completion gets truncated before it reaches a Bird.
    public static string? Clean(string? raw, int maxLength)
    {
        var text = raw?.Trim().Trim('"', '“', '”').Trim();
        if (string.IsNullOrEmpty(text)) return null;
        return text.Length > maxLength ? text[..maxLength] : text;
    }
}
