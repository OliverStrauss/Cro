using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class HubPictureService : IHubPictureService
{
    private readonly BlobContainerClient _container;
    private readonly IHubRepository _hubRepository;
    private readonly IHubPictureSuggestionRepository _suggestionRepository;

    public HubPictureService(
        BlobServiceClient blobServiceClient,
        IHubRepository hubRepository,
        IHubPictureSuggestionRepository suggestionRepository,
        IOptions<BlobStorageOptions> options)
    {
        _container = blobServiceClient.GetBlobContainerClient(options.Value.HubPicturesContainerName);
        _hubRepository = hubRepository;
        _suggestionRepository = suggestionRepository;
    }

    // Any authenticated user can suggest a photo for an existing Approved Hub - unlike
    // Hub location suggestions, there's no separate Pending Hub involved, just a Pending
    // picture attached to an already-live Hub. The upload lands in blob storage
    // immediately (so it's previewable in the admin moderation feed before approval); it
    // only becomes the Hub's actual picture once ApproveAsync below runs. Blob named after
    // the *suggestion's* own id, not the Hub's, so several pending suggestions for the same
    // Hub can coexist without overwriting each other before one is chosen.
    public async Task<HubPictureSuggestion> SuggestAsync(string hubId, string userId, Stream content, string contentType, long contentLength)
    {
        if (!ImageUploadValidation.AllowedContentTypes.Contains(contentType))
        {
            throw new HubPictureServiceException(400, "Unsupported image type.");
        }
        if (contentLength > ImageUploadValidation.MaxSizeBytes)
        {
            throw new HubPictureServiceException(400, "Image is too large (5MB max).");
        }

        var hub = await _hubRepository.GetAsync(hubId)
            ?? throw new HubPictureServiceException(404, "Hub not found.");
        if (hub.Status != HubStatus.Approved)
        {
            throw new HubPictureServiceException(409, "Only an approved Hub can receive a photo suggestion.");
        }

        var suggestionId = Guid.NewGuid().ToString();
        var blob = _container.GetBlobClient(suggestionId);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        var suggestion = new HubPictureSuggestion(suggestionId, hub.Id, userId, blob.Uri.ToString(), DateTimeOffset.UtcNow);
        return await _suggestionRepository.CreateAsync(suggestion);
    }

    public Task<List<HubPictureSuggestion>> ListPendingAsync() => _suggestionRepository.ListPendingAsync();

    // Approving points the Hub's own ProfilePictureUrl at the already-uploaded suggestion
    // blob (no re-upload/copy needed) and removes the suggestion row.
    public async Task<Hub> ApproveAsync(string suggestionId)
    {
        var suggestion = await _suggestionRepository.GetAsync(suggestionId)
            ?? throw new HubPictureServiceException(404, "Suggestion not found.");
        var hub = await _hubRepository.GetAsync(suggestion.HubId)
            ?? throw new HubPictureServiceException(404, "Hub not found.");

        var updated = await _hubRepository.UpdateAsync(hub with { ProfilePictureUrl = suggestion.BlobUrl });
        await _suggestionRepository.DeleteAsync(suggestion.Id, suggestion.HubId);
        return updated;
    }

    // Rejecting removes both the suggestion row and its blob - unlike an approved
    // suggestion's blob, a rejected one has no reason to stick around.
    public async Task RejectAsync(string suggestionId)
    {
        var suggestion = await _suggestionRepository.GetAsync(suggestionId)
            ?? throw new HubPictureServiceException(404, "Suggestion not found.");

        await _container.GetBlobClient(suggestion.Id).DeleteIfExistsAsync();
        await _suggestionRepository.DeleteAsync(suggestion.Id, suggestion.HubId);
    }
}
