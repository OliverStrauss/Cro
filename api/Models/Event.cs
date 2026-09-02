using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID, and UserId (whose timeline/notification list this belongs to) is
// the partition key - same single-partition-per-owner reasoning as Waypoint/Bird. Written
// once, at the moment something happens (a bird departs/arrives, a hub post lands, a friend
// request is accepted), and never updated afterward except IsRead flipping via the
// notifications endpoints. DisplayText is fully rendered at write time from whatever data is
// available then - never re-derived from a live Bird/HubMessage/User lookup later, because
// those can be deleted (Bird) or TTL-expire (HubMessage) while this record must not. This is
// the one place in the backend that intentionally never gets pruned - the web UI's "journey
// log" reads this as a permanent history, and the notification bell reads the IsNotification
// subset of it. QuotedNote/TargetType/TargetId are optional: QuotedNote carries a snapshotted
// payload excerpt for the timeline's quoted-note blocks, TargetType/TargetId let a
// notification or timeline entry deep-link back to the still-live Bird/Nest/Hub it's about
// (null once that's not applicable, e.g. a friend-request notification just routes to the
// Friends screen client-side). SourceUserId is null for anything that isn't "someone else did
// this to you" (self-only kinds like BirdDeparted/BirdArrived never set it) - where it is set
// (BirdArrivedAtYourNest, FriendRequestAccepted) it's the other user's id, letting the web UI
// tint that notification with the sender's own friend color without re-deriving it from
// DisplayText, which is free-form and not guaranteed to name them.
public record Event(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Kind,
    string DisplayText,
    string? QuotedNote,
    string? TargetType,
    string? TargetId,
    bool IsNotification,
    bool IsRead,
    DateTimeOffset CreatedAt,
    string? SourceUserId = null);

public static class EventKind
{
    public const string BirdDeparted = "BirdDeparted";
    public const string BirdArrived = "BirdArrived";
    public const string BirdArrivedAtYourNest = "BirdArrivedAtYourNest";
    public const string HubPostCreated = "HubPostCreated";
    public const string BirdJoinedFlock = "BirdJoinedFlock";
    public const string FriendAdded = "FriendAdded";
    public const string FriendRequestAccepted = "FriendRequestAccepted";
    public const string FriendRequestReceived = "FriendRequestReceived";
}

public static class EventTargetType
{
    public const string Bird = "Bird";
    public const string Nest = "Nest";
    public const string Hub = "Hub";
}
