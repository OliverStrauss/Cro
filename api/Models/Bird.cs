using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID (a user always has exactly 3 of these), and UserId is the owning
// user's id and the partition key - same single-partition-per-owner reasoning as Waypoint.
// CurrentNestId is null until the owner creates their first nest (see the auto-assignment
// hook on POST /waypoints in Program.cs) or while the bird is mid-flight (IsTraveling=true) -
// NestFromId/NestToId hold the journey's endpoints in that case. Type is a species from
// BirdTypeCatalog, assigned once at creation, and drives the bird's base travel speed. Speed
// snapshots the *effective* km/h used for a given journey (base speed x the universal
// BirdTravelOptions multiplier at send time) so a later multiplier change doesn't retroactively
// alter an in-flight ETA. DepartedAt/EstimatedArrivalAt are null while idle; EstimatedArrivalAt
// is what BirdService's lazy arrival-resolution compares against UtcNow. IsRead is true for
// idle/never-arrived birds and flips false the moment any arrival is resolved (self-sent or
// from someone else - no special-casing), flipping back to true via the read endpoint.
public record Bird(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Name,
    string? CurrentNestId,
    bool IsTraveling,
    string? NestFromId,
    string? NestToId,
    double? Speed,
    string? Content,
    string Type,
    DateTimeOffset? DepartedAt,
    DateTimeOffset? EstimatedArrivalAt,
    bool IsRead,
    DateTimeOffset UpdatedAt);
