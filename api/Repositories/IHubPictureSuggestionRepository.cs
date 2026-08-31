using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IHubPictureSuggestionRepository
{
    Task<HubPictureSuggestion> CreateAsync(HubPictureSuggestion suggestion);
    Task<List<HubPictureSuggestion>> ListPendingAsync();
    Task<HubPictureSuggestion?> GetAsync(string suggestionId);
    Task DeleteAsync(string suggestionId, string hubId);
}
