using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// A bird's own persistent avatar - mirrors NestPictureService's shape exactly, just keyed to
// IBirdRepository instead of IWaypointRepository. Distinct from BirdMediaService, which
// uploads a specific sent message's payload media (Parrot's audio, Pigeon/Raven's image).
public class BirdPictureService : IBirdPictureService
{
    private readonly BlobContainerClient _container;
    private readonly IBirdRepository _birdRepository;

    public BirdPictureService(
        BlobServiceClient blobServiceClient,
        IBirdRepository birdRepository,
        IOptions<BlobStorageOptions> options)
    {
        _container = blobServiceClient.GetBlobContainerClient(options.Value.BirdPicturesContainerName);
        _birdRepository = birdRepository;
    }

    public async Task<string> UploadAsync(string userId, string birdId, Stream content, string contentType, long contentLength)
    {
        if (!BirdMediaValidation.AllowedImageContentTypes.Contains(contentType))
        {
            throw new BirdPictureServiceException(400, "Unsupported image type.");
        }

        if (contentLength > BirdMediaValidation.MaxImageSizeBytes)
        {
            throw new BirdPictureServiceException(400, "Image is too large (5MB max).");
        }

        var bird = await _birdRepository.GetAsync(userId, birdId)
            ?? throw new BirdPictureServiceException(404, "Bird not found.");

        var blob = _container.GetBlobClient(birdId);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        var url = blob.Uri.ToString();
        await _birdRepository.UpdateAsync(bird with { ProfilePictureUrl = url });
        return url;
    }
}
