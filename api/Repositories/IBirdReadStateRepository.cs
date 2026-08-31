using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IBirdReadStateRepository
{
    Task<List<BirdReadState>> ListForUserAsync(string userId);
    Task MarkReadAsync(string userId, string birdId, DateTimeOffset readAt);
}
