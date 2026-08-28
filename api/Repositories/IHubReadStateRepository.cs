using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IHubReadStateRepository
{
    Task<List<HubReadState>> ListForUserAsync(string userId);
    Task MarkReadAsync(string userId, string hubId, DateTimeOffset readAt);
}
