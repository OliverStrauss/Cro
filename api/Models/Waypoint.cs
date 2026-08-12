using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID (a user has exactly one private and one public nest, see
// IsPublic below), and UserId is the owning user's id and the partition key - one
// partition per user keeps "list all of a user's nests" a single-partition query and
// "get/update/delete one nest" a point op. IsPublic is set once at creation
// (WaypointService rejects a second nest of the same kind) and is not editable
// afterward, since flipping it could silently violate the one-of-each invariant.
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
