using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// One row per photo suggested for a Hub, awaiting admin review - mirrors the Hub
// location suggestion/approval flow (see HubStatus.Pending), but doesn't need its own
// status partition since rejecting a suggestion just deletes the row outright, same as
// rejecting a pending Hub. HubId is the partition key: the dominant per-hub query is
// "pending photo suggestions for this hub", same /hubId reasoning as HubMessage. The
// admin moderation feed (every pending suggestion across every Hub) is a small-volume
// cross-partition scan, acceptable at a curated Hub list's size.
public record HubPictureSuggestion(
    [property: JsonPropertyName("id")] string Id,
    string HubId,
    string SuggestedByUserId,
    string BlobUrl,
    DateTimeOffset CreatedAt);
