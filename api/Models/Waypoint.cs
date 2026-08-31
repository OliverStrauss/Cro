using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID, and UserId is the owning user's id and the partition key - one
// partition per user keeps "list all of a user's nests" a single-partition query and
// "get/update/delete one nest" a point op. A user gets exactly one personal nest total
// (WaypointService rejects a second, of either kind), always created private now that the
// frontend no longer offers a public choice - Hubs are the only public landmark type.
// IsPublic is set once at creation and not editable afterward; older nests created back
// when the choice existed may still be true.
// ProfilePictureUrl is the nest's own picture, set via PUT /waypoints/{id}/picture - null
// until the nest's author sets one, in which case callers fall back to the owner's own
// profile picture (resolved at the /waypoints and /friends/waypoints endpoints, not stored
// here) rather than leaving the nest markerless.
public record Waypoint(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Name,
    double Latitude,
    double Longitude,
    DateTimeOffset UpdatedAt,
    bool IsPublic = false,
    string? ProfilePictureUrl = null);
