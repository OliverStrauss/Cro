namespace CroApp.Api.Services;

public interface IBirdMediaService
{
    Task<string> UploadAsync(string birdId, BirdMediaKind kind, Stream content, string contentType, long contentLength);
}
