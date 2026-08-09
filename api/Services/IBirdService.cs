using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IBirdService
{
    Task<List<Bird>> ListAsync(string userId);
    Task AssignUnassignedBirdsToNestAsync(string userId, string nestId);
}
