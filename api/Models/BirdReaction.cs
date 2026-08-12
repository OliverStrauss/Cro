using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is deterministic ("{BirdId}:{UserId}:{Emoji}"), not a generated GUID - makes "add this
// reaction" a plain idempotent upsert (no read-then-write race) and naturally enforces "a
// user can't stack the same emoji on the same bird twice" without a separate uniqueness
// check. BirdId is the partition key: Bird is partitioned by the *sender's* userId, and a
// reaction from a different user writing into that document would be a cross-partition
// write keyed by someone else's partition, with concurrent reactions on a popular public
// bird racing on one document - partitioning Reactions by /birdId instead makes every
// reaction read/write single-partition regardless of who's reacting, and never touches the
// Bird document itself.
public static class BirdReactionEmoji
{
    public static readonly HashSet<string> Allowed = ["👍", "❤️", "😂", "😮", "🎉"];
}

public record BirdReaction(
    [property: JsonPropertyName("id")] string Id,
    string BirdId,
    string UserId,
    string Emoji,
    DateTimeOffset CreatedAt)
{
    public static string BuildId(string birdId, string userId, string emoji) => $"{birdId}:{userId}:{emoji}";
}
