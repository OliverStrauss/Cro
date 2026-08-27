using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IHubRepository
{
    Task<List<Hub>> ListApprovedAsync();
    Task<Hub?> GetAsync(string hubId);
    Task<Hub> CreateAsync(Hub hub);
}
