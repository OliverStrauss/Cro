using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IBirdService
{
    Task<List<Bird>> ListAsync(string userId);
    Task<List<Bird>> ListTravelingAsync(string userId);
    Task AssignUnassignedBirdsToNestAsync(string userId, string nestId);
    Task<Bird> SendAsync(string userId, string birdId, string destinationNestId, string? content);
    Task<List<Bird>> GetNestResidentsAsync(string userId, string nestId);
    Task<List<Bird>> GetHubResidentsAsync(string hubId);
    Task<Bird> MarkReadAsync(string userId, string birdId);
}
