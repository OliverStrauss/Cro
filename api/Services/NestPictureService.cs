using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class NestPictureService(
    PictureUploadService uploader,
    CosmosWaypointRepository waypointRepository,
    IOptions<BlobStorageOptions> options)
{
    // Blob named after the nest's own id, not the owner's - unlike ProfilePictureService's
    // one-per-user blob, a user can have up to 5 nests, each needing a distinct picture.
    public Task<string> UploadAsync(string userId, string waypointId, Stream content, string contentType, long contentLength) =>
        uploader.UploadAsync(
            options.Value.NestPicturesContainerName,
            blobKey: waypointId,
            content, contentType, contentLength,
            ImageUploadValidation.AllowedContentTypes, ImageUploadValidation.MaxSizeBytes,
            fetch: () => waypointRepository.GetAsync(userId, waypointId),
            notFoundMessage: "Nest not found.",
            save: (waypoint, url) => waypointRepository.UpdateAsync(waypoint with { ProfilePictureUrl = url }));
}
