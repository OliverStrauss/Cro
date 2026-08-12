namespace CroApp.Api.Services;

public class HubServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
