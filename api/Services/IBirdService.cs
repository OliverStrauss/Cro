using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IBirdService
{
    Task<List<Bird>> ListAsync(string userId);
    Task AssignUnassignedBirdsToNestAsync(string userId, string nestId);
    Task<Bird> SendAsync(string userId, string birdId, string destinationNestId, string? content);
    Task<List<Bird>> GetNestResidentsAsync(string userId, string nestId);
    Task<Bird> MarkReadAsync(string userId, string birdId);
}
