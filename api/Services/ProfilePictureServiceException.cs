namespace CroApp.Api.Services;

public class ProfilePictureServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
