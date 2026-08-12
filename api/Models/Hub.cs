using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID, and Status is the partition key - the dominant query is "list
// every approved Hub" (a handful of rows, read far more than written), which a /status
// partition keeps single-partition even once a future "Pending" status (user-proposed
// Hubs, not built yet) starts accumulating its own rows. Unlike Waypoint, a Hub has no
// single user-owner - CreatedByUserId just records who placed it, it isn't a partition
// key or an ownership check the way Waypoint.UserId is. Status is a plain string (not an
// enum) so a future proposal/approval flow doesn't require a schema migration; only
// "Approved" is ever produced by the admin-placement flow this pass.
public record Hub(
    [property: JsonPropertyName("id")] string Id,
    string Name,
    double Latitude,
    double Longitude,
    string Status,
    string CreatedByUserId,
    DateTimeOffset CreatedAt,
    string? Category = null,
    string? ProfilePictureUrl = null);

public static class HubStatus
{
    public const string Approved = "Approved";
}
