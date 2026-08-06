namespace CroApp.Api.Services;

public interface IFriendService
{
    Task SendRequestAsync(string requesterId, string targetUsername);
    Task AcceptAsync(string userId, string requesterId);
    Task RemoveAsync(string userId, string otherUserId);
    Task SetColorAsync(string userId, string friendId, string color);
}
