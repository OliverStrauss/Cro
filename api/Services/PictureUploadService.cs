using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

namespace CroApp.Api.Services;

// Shared validate/upload/save-url flow behind BirdPictureService, NestPictureService, and
// ProfilePictureService - each just supplies its own repository lookup/update, container, and
// blob key.
public class PictureUploadService(BlobServiceClient blobServiceClient)
{
    public async Task<string> UploadAsync<T>(
        string containerName,
        string blobKey,
        Stream content,
        string contentType,
        long contentLength,
        IReadOnlySet<string> allowedContentTypes,
        long maxSizeBytes,
        Func<Task<T?>> fetch,
        string notFoundMessage,
        Func<T, string, Task> save) where T : class
    {
        if (!allowedContentTypes.Contains(contentType))
        {
            throw new ServiceException(400, "Unsupported image type.");
        }

        if (contentLength > maxSizeBytes)
        {
            throw new ServiceException(400, "Image is too large (5MB max).");
        }

        var entity = await fetch() ?? throw new ServiceException(404, notFoundMessage);

        var blob = blobServiceClient.GetBlobContainerClient(containerName).GetBlobClient(blobKey);
        await blob.UploadAsync(content, new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
        });

        var url = blob.Uri.ToString();
        await save(entity, url);
        return url;
    }
}
