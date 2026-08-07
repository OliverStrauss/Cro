namespace CroApp.Api.Models;

// Explicit whitelist, same as before - PasswordHash and Friends must never appear here.
// ProfilePictureUrl is fine to include: unlike the friends graph, it isn't privacy-sensitive,
// and this endpoint being public/unauthenticated is exactly how friends can view it.
public record UserResponse(string Id, string Username, string Email, DateTimeOffset CreatedAt, string? ProfilePictureUrl);

public static class UserExtensions
{
    public static UserResponse ToResponse(this User user) =>
        new(user.Id, user.Username, user.Email, user.CreatedAt, user.ProfilePictureUrl);
}
