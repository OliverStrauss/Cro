namespace CroApp.Api.Services;

public interface INestPictureService
{
    Task<string> UploadAsync(string userId, string waypointId, Stream content, string contentType, long contentLength);
}
