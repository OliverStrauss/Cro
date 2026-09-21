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
//
// ActChance is the per-tick odds (0-1) a bot does anything spontaneous - rolled in C#, so a
// failed roll never calls the LLM (replies to an unread inbox skip the roll). The four
// *Weight values set the mix once a bot does act: FriendWeight = private cro to a human
// friend, PublicWeight = public cro to a human friend, BotWeight = cro to a bot friend,
// HubWeight = post to a random approved Hub; an action with no valid target is dropped from
// the draw. ShooAfterHours is how long someone else's already-read bird may rest at a
// bot's home nest before the bot shoos it back home; RecallAfterHours is how long the bot's
// own bird may rest at another nest or Hub before the bot sends it back to its home nest.
// PinChance (0-1) is the odds a bot pins each unread inbound cro before answering it - 1.0
// for now so every conversation is logged.
public class BotOrchestratorOptions
{
    public int TickIntervalSeconds { get; set; } = 60;
    public int TickCooldownMinutes { get; set; } = 30;
    public int MaxConsecutiveBotReplies { get; set; } = 3;
    public int MaxReplyContentLength { get; set; } = 500;
    public double ActChance { get; set; } = 0.5;
    public int FriendWeight { get; set; } = 35;
    public int PublicWeight { get; set; } = 20;
    public int BotWeight { get; set; } = 15;
    public int HubWeight { get; set; } = 30;
    public int ShooAfterHours { get; set; } = 24;
    public int RecallAfterHours { get; set; } = 12;
    public double PinChance { get; set; } = 1.0;
}
