using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// One row per bird that has ever landed at a Hub - written once, at arrival, by
// BirdService.ResolveArrivalIfDueAsync, and never updated afterward. Deliberately durable
// independent of the underlying Bird's own lifecycle: unlike GetHubResidentsAsync (a live
// "who's currently sitting here" snapshot), a HubMessage survives the bird later being
// picked up and resent elsewhere, or even deleted. HubId is the partition key - the
// dominant query is "list every message posted to a given Hub, newest first", same
// reasoning as Hub's own /status and BirdReaction's /birdId. The container's
// DefaultTimeToLive (see Program.cs) auto-expires rows 7 days after CreatedAt, so the
// board resets itself with no cleanup job. SenderProfilePictureUrl is deliberately NOT
// stored here - resolved live at read time via the same N+1 pattern GET /friends already
// uses, so an avatar changed after posting still shows up-to-date on old board entries.
public record HubMessage(
    [property: JsonPropertyName("id")] string Id,
    string HubId,
    string BirdId,
    string SenderId,
    string SenderUsername,
    string BirdName,
    string? OriginNestName,
    string Type,
    string? Content,
    string? AudioUrl,
    string? ImageUrl,
    DateTimeOffset CreatedAt);
