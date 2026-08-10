using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class NestPictureService : INestPictureService
{
    private readonly BlobContainerClient _container;
    private readonly IWaypointRepository _waypointRepository;

    public NestPictureService(
        BlobServiceClient blobServiceClient,
        IWaypointRepository waypointRepository,
        IOptions<BlobStorageOptions> options)
    {
        _container = blobServiceClient.GetBlobContainerClient(options.Value.NestPicturesContainerName);
        _waypointRepository = waypointRepository;
    }

    public async Task<string> UploadAsync(string userId, string waypointId, Stream content, string contentType, long contentLength)
    {
        if (!ImageUploadValidation.AllowedContentTypes.Contains(contentType))
        {
            throw new NestPictureServiceException(400, "Unsupported image type.");
        }

        if (contentLength > ImageUploadValidation.MaxSizeBytes)
        {
            throw new NestPictureServiceException(400, "Image is too large (5MB max).");
        }

        var waypoint = await _waypointRepository.GetAsync(userId, waypointId)
            ?? throw new NestPictureServiceException(404, "Nest not found.");

        // Blob named after the nest's own id, not the owner's - unlike ProfilePictureService's
        // one-per-user blob, a user can have up to 5 nests, each needing a distinct picture.
        var blob = _container.GetBlobClient(waypointId);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        var url = blob.Uri.ToString();
        await _waypointRepository.UpdateAsync(waypoint with { ProfilePictureUrl = url });
        return url;
    }
}
