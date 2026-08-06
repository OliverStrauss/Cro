namespace CroApp.Api.Services;

public class FriendServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
