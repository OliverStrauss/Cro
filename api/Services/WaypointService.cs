using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public class WaypointService(CosmosWaypointRepository waypointRepository)
{
    public Task<List<Waypoint>> ListAsync(string userId) => waypointRepository.ListByUserIdAsync(userId);

    public async Task<Waypoint> CreateAsync(string userId, string name, double latitude, double longitude, bool isPublic)
    {
        var existing = await waypointRepository.ListByUserIdAsync(userId);
        if (existing.Count > 0)
        {
            throw new ServiceException(409, "You already have a nest. Delete it before adding another.");
        }

        var waypoint = new Waypoint(Guid.NewGuid().ToString(), userId, name, latitude, longitude, DateTimeOffset.UtcNow, isPublic);
        return await waypointRepository.CreateAsync(waypoint);
    }

    public async Task<Waypoint> UpdateAsync(string userId, string waypointId, string name, double latitude, double longitude)
    {
        var existing = await waypointRepository.GetAsync(userId, waypointId)
            ?? throw new ServiceException(404, "Nest not found.");

        var updated = existing with { Name = name, Latitude = latitude, Longitude = longitude, UpdatedAt = DateTimeOffset.UtcNow };
        return await waypointRepository.UpdateAsync(updated);
    }

    public async Task DeleteAsync(string userId, string waypointId)
    {
        var deleted = await waypointRepository.DeleteAsync(userId, waypointId);
        if (!deleted)
        {
            throw new ServiceException(404, "Nest not found.");
        }
    }
}
