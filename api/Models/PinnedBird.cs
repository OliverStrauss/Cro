using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// A durable "saved message" snapshot of a bird that landed at the receiver's own nest -
// same reasoning as HubMessage (a bird is a reusable carrier, so its live Content/media get
// overwritten the next time it's sent), just for a direct delivery instead of a Hub arrival.
// ReceiverId is the partition key: the dominant query is "list everything I've pinned"
// (GET /pins/mine), single-partition per receiver, same as HubMessage's /hubId. IsPublic is
// snapshotted from the bird's own IsPublic at pin time - it decides whether GET /pins/public
// (a cross-partition scan, same shape as GET /birds/public) surfaces this pin to everyone, or
// only the receiver ever sees it. Id is deterministic ("{BirdId}:{ReceiverId}:{DeliveredAtTicks}")
// so re-tapping "pin" on the same still-resident delivery is an idempotent upsert instead of a
// duplicate row - DeliveredAtTicks (the bird's UpdatedAt at the moment it last arrived) is what
// identifies *this* delivery, since the same BirdId gets reused across many later journeys.
public record PinnedBird(
    [property: JsonPropertyName("id")] string Id,
    string ReceiverId,
    string SenderId,
    string SenderUsername,
    string BirdId,
    string BirdName,
    string? OriginNestName,
    // The nest the bird landed on, captured at pin time - nullable because pins made before
    // this field existed have none, and simply aren't navigable to a nest (no backfill).
    string? WaypointId,
    string Type,
    string? Content,
    string? AudioUrl,
    string? ImageUrl,
    bool IsPublic,
    DateTimeOffset CreatedAt)
{
    public static string BuildId(string birdId, string receiverId, DateTimeOffset deliveredAt) =>
        $"{birdId}:{receiverId}:{deliveredAt.UtcTicks}";
}
