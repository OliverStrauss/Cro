namespace CroApp.Api.Services;

public class EventServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
