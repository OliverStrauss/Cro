namespace CroApp.Api.Services;

public interface IBirdPictureService
{
    Task<string> UploadAsync(string userId, string birdId, Stream content, string contentType, long contentLength);
}
