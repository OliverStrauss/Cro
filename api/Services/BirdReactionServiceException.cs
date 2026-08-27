namespace CroApp.Api.Services;

public class BirdReactionServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
