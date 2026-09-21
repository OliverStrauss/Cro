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
// WatchedHubIds is the fixed set of Hubs this bot is willing to post to (BotOrchestratorService
// never lets a bot discover/post to a Hub outside this list - an admin-curated allowlist, not
// "every approved Hub", so a bot's presence on the map stays intentional). ConsecutiveBotReplies
// counts, per other-bot-userId, how many times in a row this bot has chosen to message that
// specific bot without an intervening human interaction - BotOrchestratorService reads it to
// cap back-and-forth bot chatter (see BotOrchestratorOptions.MaxConsecutiveBotReplies) and
// resets the *whole* dictionary to empty the moment the bot messages or replies to a human,
// modeling "got distracted by a person, dropped the bot thread" rather than tracking each
// pairing's cooldown independently. LastTickAt is null until the bot's first tick;
// BotOrchestratorService compares it against BotOrchestratorOptions.TickCooldownMinutes to
// keep a bot from acting on literally every orchestrator sweep.
public record BotProfile(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Persona,
    string Model,
    bool IsEnabled,
    List<string> WatchedHubIds,
    Dictionary<string, int> ConsecutiveBotReplies,
    DateTimeOffset? LastTickAt,
    DateTimeOffset UpdatedAt);
