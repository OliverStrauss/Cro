namespace CroApp.Api.Services;

public interface IProfilePictureService
{
    Task<string> UploadAsync(string userId, Stream content, string contentType, long contentLength);
}
