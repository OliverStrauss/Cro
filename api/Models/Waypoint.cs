using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is intentionally the owning user's id, not a generated GUID - one waypoint per
// user means the user's own id is a natural, collision-free document key and partition key.
public record Waypoint(
    [property: JsonPropertyName("id")] string Id,
    string Name,
    double Latitude,
    double Longitude,
    DateTimeOffset UpdatedAt);
