using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IHubService
{
    Task<List<Hub>> ListApprovedAsync();
    Task<Hub> CreateAsync(string createdByUserId, string name, double latitude, double longitude, string category);
    Task<Hub> GetAsync(string hubId);
    Task<Hub> SuggestAsync(string suggestedByUserId, string name, double latitude, double longitude, string category);
    Task<List<Hub>> ListPendingAsync();
    Task<Hub> ApproveAsync(string hubId);
    Task RejectAsync(string hubId);
}
