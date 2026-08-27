using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public class HubService(IHubRepository hubRepository) : IHubService
{
    public Task<List<Hub>> ListApprovedAsync() => hubRepository.ListApprovedAsync();

    public async Task<Hub> CreateAsync(string createdByUserId, string name, double latitude, double longitude, string? category)
    {
        var hub = new Hub(
            Guid.NewGuid().ToString(),
            name,
            latitude,
            longitude,
            HubStatus.Approved,
            createdByUserId,
            DateTimeOffset.UtcNow,
            category);
        return await hubRepository.CreateAsync(hub);
    }

    public async Task<Hub> GetAsync(string hubId) =>
        await hubRepository.GetAsync(hubId) ?? throw new HubServiceException(404, "Hub not found.");
}
