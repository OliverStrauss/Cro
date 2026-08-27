using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IHubService
{
    Task<List<Hub>> ListApprovedAsync();
    Task<Hub> CreateAsync(string createdByUserId, string name, double latitude, double longitude, string? category);
    Task<Hub> GetAsync(string hubId);
}
