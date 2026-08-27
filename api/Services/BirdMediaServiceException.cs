namespace CroApp.Api.Services;

public class BirdMediaServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
