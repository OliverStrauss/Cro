namespace CroApp.Api.Services;

public class HubPictureServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
