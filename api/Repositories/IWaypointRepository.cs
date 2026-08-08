using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IWaypointRepository
{
    Task<List<Waypoint>> ListByUserIdAsync(string userId);
    Task<Waypoint?> GetAsync(string userId, string waypointId);
    Task<Waypoint> CreateAsync(Waypoint waypoint);
    Task<Waypoint> UpdateAsync(Waypoint waypoint);
    Task<bool> DeleteAsync(string userId, string waypointId);
    Task<List<Waypoint>> GetManyByUserIdsAsync(IEnumerable<string> userIds);
}
