using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IWaypointRepository
{
    Task<Waypoint?> GetByUserIdAsync(string userId);
    Task<Waypoint> UpsertAsync(Waypoint waypoint);
}
