using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID, and UserId is the owning user's id and the partition key - same
// single-partition-per-owner reasoning as Waypoint. A user spawns birds on demand (capped at
// MaxBirdsPerUser, see BirdService) rather than owning a fixed auto-provisioned set - Name is
// user-supplied at compose time, not auto-generated. CurrentNestId is null while mid-flight
// (IsTraveling=true), in which case NestFromId/NestToId hold the journey's endpoints. Type is
// one of BirdTypeCatalog's four types, chosen once at compose time, and drives both the
// bird's base travel speed and which payload fields are required (see BirdPayloadValidator):
// Content for Cro/Raven, AudioUrl for Parrot, ImageUrl for Pigeon/Raven. ProfilePictureUrl is
// the bird's own persistent avatar - distinct from AudioUrl/ImageUrl, which hold a specific
// sent message's payload media, same split Waypoint has between its own picture and message
// content. IsPublic is set at compose time; true means the bird is readable/reactable by
// anyone, not just its recipient. Speed snapshots the *effective* km/h used for a given
// journey (base speed x the universal BirdTravelOptions multiplier at send time) so a later
// multiplier change doesn't retroactively alter an in-flight ETA. DepartedAt/EstimatedArrivalAt
// are null while idle; EstimatedArrivalAt is what BirdService's lazy arrival-resolution
// compares against UtcNow. IsRead is true for idle/never-arrived birds and flips false the
// moment any arrival is resolved (self-sent or from someone else - no special-casing),
// flipping back to true via the read endpoint.
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
    DateTimeOffset UpdatedAt,
    string? AudioUrl = null,
    string? ImageUrl = null,
    string? ProfilePictureUrl = null,
    bool IsPublic = false);
