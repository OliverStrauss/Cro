namespace CroApp.Api.Services;

public class BirdServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
