namespace CroApp.Api.Services;

public interface IFriendService
{
    Task SendRequestAsync(string requesterId, string targetUsername);
    Task AcceptAsync(string userId, string requesterId);
    Task RemoveAsync(string userId, string otherUserId);
    Task DeclineAsync(string userId, string requesterId);
    Task SetColorAsync(string userId, string friendId, string color);
    Task BlockAsync(string userId, string targetId);
    Task UnblockAsync(string userId, string targetId);
    Task<List<string>> ListBlockedAsync(string userId);
}
