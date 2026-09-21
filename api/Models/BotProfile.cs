using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// The bot-specific data an LLM-driven User (User.IsBot = true) carries in addition to its
// ordinary User document - kept as a separate container/document rather than bloating User
// itself, same "extension document" split HubReadState/BirdReadState use for per-user state
// that isn't part of the core profile. Exactly one profile per bot, so unlike every other
// document in this app Id is deliberately set equal to UserId (not a fresh GUID) - that
// makes CosmosBotProfileRepository.GetAsync a plain ReadItemAsync(userId, PartitionKey(userId))
// point read instead of a query, and UserId is still the partition key for consistency with
// Waypoint/Bird/Event's single-partition-per-owner shape.
//
// ConsecutiveBotReplies counts, per other-bot-userId, how many times in a row this bot has chosen to message that
// specific bot without an intervening human interaction - BotOrchestratorService reads it to
// cap back-and-forth bot chatter (see BotOrchestratorOptions.MaxConsecutiveBotReplies) and
// resets the *whole* dictionary to empty the moment the bot messages or replies to a human,
// modeling "got distracted by a person, dropped the bot thread" rather than tracking each
// pairing's cooldown independently. LastTickAt is null until the bot's first tick;
// BotOrchestratorService compares it against BotOrchestratorOptions.TickCooldownMinutes to
// keep a bot from acting on literally every orchestrator sweep. Threads is the bot's memory:
// per friend user id, the last few lines of its conversation with that friend (both sides), so
// a reply isn't written cold - see BotBackdrop. Kept here rather than derived from pins because
// pins only ever hold inbound messages and a bot's own sends have no other durable copy (a
// bird's Content is overwritten on its next journey). Null on profiles that predate it.
public record BotProfile(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Persona,
    string Model,
    bool IsEnabled,
    Dictionary<string, int> ConsecutiveBotReplies,
    DateTimeOffset? LastTickAt,
    DateTimeOffset UpdatedAt,
    Dictionary<string, List<BotThreadLine>>? Threads = null);

// One line of a bot's remembered conversation with a friend - FromMe is true for what the bot
// itself sent, false for what the friend sent it.
public record BotThreadLine(bool FromMe, string Text);
