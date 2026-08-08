namespace CroApp.Api.Services;

public class WaypointServiceException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
