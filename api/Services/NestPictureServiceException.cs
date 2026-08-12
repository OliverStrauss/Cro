namespace CroApp.Api.Services;

public class NestPictureServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
