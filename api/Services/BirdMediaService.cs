using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// Uploads a composed bird's payload media (Parrot's audio clip, Pigeon/Raven's image) -
// distinct from BirdPictureService, which manages a bird's own persistent avatar in a
// separate container. Unlike NestPictureService, this doesn't read-then-update a repository
// entity: ComposeAndSendAsync generates the new bird's id up front and uploads media keyed
// by that id before the Bird document itself is created, so there's nothing to fetch here.
public class BirdMediaService : IBirdMediaService
{
    private readonly BlobContainerClient _container;

    public BirdMediaService(BlobServiceClient blobServiceClient, IOptions<BlobStorageOptions> options)
    {
        _container = blobServiceClient.GetBlobContainerClient(options.Value.BirdMediaContainerName);
    }

    public async Task<string> UploadAsync(string birdId, BirdMediaKind kind, Stream content, string contentType, long contentLength)
    {
        if (!BirdMediaValidation.AllowedContentTypes(kind).Contains(contentType))
        {
            throw new BirdMediaServiceException(400, kind == BirdMediaKind.Audio ? "Unsupported audio type." : "Unsupported image type.");
        }

        if (contentLength > BirdMediaValidation.MaxSizeBytes(kind))
        {
            var maxMb = BirdMediaValidation.MaxSizeBytes(kind) / (1024 * 1024);
            throw new BirdMediaServiceException(400, $"File is too large ({maxMb}MB max).");
        }

        // A bird carries at most one payload media file (its Type determines audio XOR
        // image, never both), so the bird id alone is an unambiguous blob key.
        var blob = _container.GetBlobClient(birdId);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        return blob.Uri.ToString();
    }
}
