using CroApp.Api.Models;

namespace CroApp.Api.Services;

public interface IHubPictureService
{
    Task<HubPictureSuggestion> SuggestAsync(string hubId, string userId, Stream content, string contentType, long contentLength);
    Task<List<HubPictureSuggestion>> ListPendingAsync();
    Task<Hub> ApproveAsync(string suggestionId);
    Task RejectAsync(string suggestionId);
}
