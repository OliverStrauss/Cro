using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IWaypointService
{
    Task<List<Waypoint>> ListAsync(string userId);
    Task<Waypoint> CreateAsync(string userId, string name, double latitude, double longitude, bool isPublic);
    Task<Waypoint> UpdateAsync(string userId, string waypointId, string name, double latitude, double longitude);
    Task DeleteAsync(string userId, string waypointId);
}
