namespace CroApp.Api.Data;

// Tunables for BotOrchestratorService's tick loop. TickIntervalSeconds is how often the
// background sweep itself runs (checking every enabled bot's cooldown); TickCooldownMinutes
// is the separate, per-bot minimum gap between actual decisions, so a bot reads as
// occasionally-active rather than firing on every sweep - the two are independent so the
// sweep can stay cheap and frequent while each bot still paces itself. MaxConsecutiveBotReplies
// caps back-and-forth bot-to-bot volleys (see BotProfile.ConsecutiveBotReplies) before a bot
// stops initiating to that other bot until a human interaction resets the counter.
// MaxReplyContentLength is a defensive cap on however much text the LLM hands back - BirdService
// itself has no content-length limit today (see TECH_DEBT.md), so this is the one place a
// runaway completion gets truncated before it ever reaches a Bird document.
public class BotOrchestratorOptions
{
    public int TickIntervalSeconds { get; set; } = 60;
    public int TickCooldownMinutes { get; set; } = 30;
    public int MaxConsecutiveBotReplies { get; set; } = 3;
    public int MaxReplyContentLength { get; set; } = 500;
}
