using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class ProfilePictureService : IProfilePictureService
{
    private readonly BlobContainerClient _container;
    private readonly IUserRepository _userRepository;

    public ProfilePictureService(
        BlobServiceClient blobServiceClient,
        IUserRepository userRepository,
        IOptions<BlobStorageOptions> options)
    {
        _container = blobServiceClient.GetBlobContainerClient(options.Value.ProfilePicturesContainerName);
        _userRepository = userRepository;
    }

    public async Task<string> UploadAsync(string userId, Stream content, string contentType, long contentLength)
    {
        if (!ImageUploadValidation.AllowedContentTypes.Contains(contentType))
        {
            throw new ProfilePictureServiceException(400, "Unsupported image type.");
        }

        if (contentLength > ImageUploadValidation.MaxSizeBytes)
        {
            throw new ProfilePictureServiceException(400, "Image is too large (5MB max).");
        }

        var user = await _userRepository.GetByIdAsync(userId)
            ?? throw new ProfilePictureServiceException(404, "User not found.");

        // Blob named after the user's own id - one picture per user, same one-per-user
        // pattern Waypoint uses for its document id. Re-upload overwrites in place rather
        // than accumulating old pictures.
        var blob = _container.GetBlobClient(userId);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        var url = blob.Uri.ToString();
        await _userRepository.UpdateAsync(user with { ProfilePictureUrl = url });
        return url;
    }
}
