using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Friends is nullable because pre-existing user documents in Cosmos (created before this
// feature existed) have no friends field at all - deserializing them must not throw, and
// every read defends with user.Friends ?? [] rather than assuming non-null (same defensive
// pattern as the pre-Password legacy-user bug in issue #16). ProfilePictureUrl is nullable
// for the same reason - accounts created before this feature have no picture set. IsAdmin
// gates Hub-placement (POST /hubs) - checked via a per-request repository lookup rather
// than a JWT claim, so granting/revoking it doesn't require re-issuing tokens.
public record User(
    [property: JsonPropertyName("id")] string Id,
    string Username,
    string Email,
    DateTimeOffset CreatedAt,
    string PasswordHash,
    List<FriendEntry>? Friends,
    string? ProfilePictureUrl = null,
    bool IsAdmin = false);
