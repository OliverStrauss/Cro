using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID (a user can have up to 5 of these "nests"), and UserId is the
// owning user's id and the partition key - one partition per user keeps "list all of a
// user's nests" a single-partition query and "get/update/delete one nest" a point op.
public record Waypoint(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Name,
    double Latitude,
    double Longitude,
    DateTimeOffset UpdatedAt);
