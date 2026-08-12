namespace CroApp.Api.Models;

// Explicit whitelist, same as before - PasswordHash and Friends must never appear here.
// ProfilePictureUrl is fine to include: unlike the friends graph, it isn't privacy-sensitive,
// and this endpoint being public/unauthenticated is exactly how friends can view it. Same
// reasoning for IsAdmin - it's how the app knows whether to show the "Add Hub" affordance
// on the map, not a secret.
public record UserResponse(string Id, string Username, string Email, DateTimeOffset CreatedAt, string? ProfilePictureUrl, bool IsAdmin);

public static class UserExtensions
{
    public static UserResponse ToResponse(this User user) =>
        new(user.Id, user.Username, user.Email, user.CreatedAt, user.ProfilePictureUrl, user.IsAdmin);
}
