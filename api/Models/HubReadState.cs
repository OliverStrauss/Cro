using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// One row per (user, hub) pair, tracking when that user last opened that Hub's board - the
// unread-count badge on the map is just "how many HubMessages at this Hub have CreatedAt
// after LastReadAt". This can't live on HubMessage itself (unlike Bird.IsRead) because a
// Hub board is shared/public - a single message's read state can't differ per viewer. Id is
// the composite "{userId}:{hubId}" so marking a hub read is always a single-document point
// upsert, never a query. UserId is the partition key, same /userId reasoning as Waypoints
// and Birds (see Program.cs) - "list every hub I've read" is the dominant per-user query,
// used to compute every hub's badge in one round trip.
public record HubReadState(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string HubId,
    DateTimeOffset LastReadAt);
