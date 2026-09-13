using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Friends is nullable because pre-existing user documents in Cosmos (created before this
// feature existed) have no friends field at all - deserializing them must not throw, and
// every read defends with user.Friends ?? [] rather than assuming non-null (same defensive
// pattern as the pre-Password legacy-user bug in issue #16). ProfilePictureUrl is nullable
// for the same reason - accounts created before this feature have no picture set. IsAdmin
// gates Hub-placement (POST /hubs) - checked via a per-request repository lookup rather
// than a JWT claim, so granting/revoking it doesn't require re-issuing tokens.
// BlockedUserIds is nullable for the same pre-existing-document reason as Friends - every
// read defends with user.BlockedUserIds ?? []. A block is one-directional (only the
// blocker's list matters), checked from both sides in FriendService.SendRequestAsync so
// neither party can request the other. IsEmailVerified is nullable (not a non-nullable bool
// defaulting to true) for the same pre-existing-document reason as Friends/BlockedUserIds -
// null means "predates this feature, treat as verified" and every read must check
// `IsEmailVerified == false` rather than assuming a missing value is `true`. A non-nullable
// `bool IsEmailVerified = true` looks like it would give old documents the same safe default
// on deserialization, but doesn't: Cosmos's default serializer (CosmosSerializationOptions in
// Program.cs) is Newtonsoft.Json-based, and Newtonsoft does not apply a record constructor
// parameter's C# default value for a JSON property that's absent entirely - it falls back to
// the CLR default instead (`false` for bool), silently locking every pre-existing account out
// at login. IsAdmin's `= false` default never exposed this because its intended default
// happens to already equal the CLR fallback; IsEmailVerified's does not, which is exactly what
// broke old accounts here. POST /users is the only place that constructs a user with this
// explicitly false.
public record User(
    [property: JsonPropertyName("id")] string Id,
    string Username,
    string Email,
    DateTimeOffset CreatedAt,
    string PasswordHash,
    List<FriendEntry>? Friends,
    string? ProfilePictureUrl = null,
    bool IsAdmin = false,
    List<string>? BlockedUserIds = null,
    string? PasswordResetCodeHash = null,
    DateTimeOffset? PasswordResetExpiresAt = null,
    bool? IsEmailVerified = null,
    string? EmailVerificationCodeHash = null,
    DateTimeOffset? EmailVerificationExpiresAt = null);
