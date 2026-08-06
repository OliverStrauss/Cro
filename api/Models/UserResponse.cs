namespace CroApp.Api.Models;

public record UserResponse(string Id, string Username, string Email, DateTimeOffset CreatedAt);

public static class UserExtensions
{
    public static UserResponse ToResponse(this User user) =>
        new(user.Id, user.Username, user.Email, user.CreatedAt);
}
