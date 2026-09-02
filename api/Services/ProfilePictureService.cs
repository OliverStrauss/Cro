using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class ProfilePictureService(
    PictureUploadService uploader,
    CosmosUserRepository userRepository,
    IOptions<BlobStorageOptions> options)
{
    // Blob named after the user's own id - one picture per user, same one-per-user pattern
    // Waypoint uses for its document id. Re-upload overwrites in place rather than
    // accumulating old pictures.
    public Task<string> UploadAsync(string userId, Stream content, string contentType, long contentLength) =>
        uploader.UploadAsync(
            options.Value.ProfilePicturesContainerName,
            blobKey: userId,
            content, contentType, contentLength,
            ImageUploadValidation.AllowedContentTypes, ImageUploadValidation.MaxSizeBytes,
            fetch: () => userRepository.GetByIdAsync(userId),
            notFoundMessage: "User not found.",
            save: (user, url) => userRepository.UpdateAsync(user with { ProfilePictureUrl = url }));
}
