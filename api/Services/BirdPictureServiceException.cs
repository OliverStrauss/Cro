namespace CroApp.Api.Services;

public class BirdPictureServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
