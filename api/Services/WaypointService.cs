using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public class WaypointService(IWaypointRepository waypointRepository) : IWaypointService
{
    public Task<List<Waypoint>> ListAsync(string userId) => waypointRepository.ListByUserIdAsync(userId);

    public async Task<Waypoint> CreateAsync(string userId, string name, double latitude, double longitude, bool isPublic)
    {
        var existing = await waypointRepository.ListByUserIdAsync(userId);
        if (existing.Any(w => w.IsPublic == isPublic))
        {
            var kindLabel = isPublic ? "public" : "private";
            throw new WaypointServiceException(409, $"You already have a {kindLabel} nest. Delete it before adding another.");
        }

        var waypoint = new Waypoint(Guid.NewGuid().ToString(), userId, name, latitude, longitude, DateTimeOffset.UtcNow, isPublic);
        return await waypointRepository.CreateAsync(waypoint);
    }

    public async Task<Waypoint> UpdateAsync(string userId, string waypointId, string name, double latitude, double longitude)
    {
        var existing = await waypointRepository.GetAsync(userId, waypointId)
            ?? throw new WaypointServiceException(404, "Nest not found.");

        var updated = existing with { Name = name, Latitude = latitude, Longitude = longitude, UpdatedAt = DateTimeOffset.UtcNow };
        return await waypointRepository.UpdateAsync(updated);
    }

    public async Task DeleteAsync(string userId, string waypointId)
    {
        var deleted = await waypointRepository.DeleteAsync(userId, waypointId);
        if (!deleted)
        {
            throw new WaypointServiceException(404, "Nest not found.");
        }
    }
}
