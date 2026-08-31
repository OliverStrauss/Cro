using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// One row per (viewer, bird) pair, tracking whether that viewer has opened a friend's public
// bird's detail view yet - mirrors HubReadState exactly, for the same reason: a public bird's
// "have I seen this" state can't live on Bird itself (unlike a delivered bird's own
// Bird.IsRead) because it differs per *viewer*, not per owner. Only ever written for public
// birds (see the /birds/{id}/viewed endpoint) - a private bird's existence is visible on the
// map, but there's nothing for a friend to "view" until it's public. Id is the composite
// "{userId}:{birdId}" so marking a bird viewed is always a single-document point upsert,
// never a query. UserId is the partition key, same /userId reasoning as HubReadStates -
// "list every bird I've viewed" is the dominant per-user query, used to compute the public
// bird badge for every friend's bird on GET /friends/birds in one round trip.
public record BirdReadState(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string BirdId,
    DateTimeOffset ReadAt);
