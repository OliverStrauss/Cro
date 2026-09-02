using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// A bird's own persistent avatar - keyed to CosmosBirdRepository instead of
// CosmosWaypointRepository. Distinct from BirdMediaService, which uploads a specific sent
// message's payload media (Parrot's audio, Pigeon/Raven's image).
public class BirdPictureService(
    PictureUploadService uploader,
    CosmosBirdRepository birdRepository,
    IOptions<BlobStorageOptions> options)
{
    public Task<string> UploadAsync(string userId, string birdId, Stream content, string contentType, long contentLength) =>
        uploader.UploadAsync(
            options.Value.BirdPicturesContainerName,
            blobKey: birdId,
            content, contentType, contentLength,
            BirdMediaValidation.AllowedImageContentTypes, BirdMediaValidation.MaxImageSizeBytes,
            fetch: () => birdRepository.GetAsync(userId, birdId),
            notFoundMessage: "Bird not found.",
            save: (bird, url) => birdRepository.UpdateAsync(bird with { ProfilePictureUrl = url }));
}
