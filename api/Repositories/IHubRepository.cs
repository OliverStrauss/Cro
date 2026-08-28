using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IHubRepository
{
    Task<List<Hub>> ListApprovedAsync();
    Task<List<Hub>> ListByStatusAsync(string status);
    Task<Hub?> GetAsync(string hubId);
    Task<Hub> CreateAsync(Hub hub);
    Task DeleteAsync(string hubId, string status);
}
