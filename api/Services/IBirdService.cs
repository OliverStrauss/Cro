using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IBirdService
{
    Task<List<Bird>> ListAsync(string userId);
    Task<List<Bird>> ListTravelingAsync(string userId);
    Task<Bird> ComposeAndSendAsync(
        string userId,
        string type,
        string name,
        string originNestId,
        string destinationId,
        string? content,
        bool isPublic,
        Stream? mediaStream,
        string? mediaContentType,
        long mediaContentLength);
    Task<Bird> SendAsync(string userId, string birdId, string destinationNestId, string? content);
    Task<Bird> RenameAsync(string userId, string birdId, string name);
    Task DeleteAsync(string userId, string birdId);
    Task<List<Bird>> GetNestResidentsAsync(string userId, string nestId);
    Task<List<Bird>> GetHubResidentsAsync(string hubId);
    Task<Bird> MarkReadAsync(string userId, string birdId);
}
