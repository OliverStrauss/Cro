using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class WaypointPictureEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    private const string DefaultAzuriteConnectionString = "UseDevelopmentStorage=true";

    private readonly HttpClient _client;

    public WaypointPictureEndpointTests(WebApplicationFactory<Program> factory)
    {
        var cosmosConnectionString = Environment.GetEnvironmentVariable("CosmosDb__ConnectionString")
            ?? DefaultEmulatorConnectionString;
        var blobConnectionString = Environment.GetEnvironmentVariable("BlobStorage__ConnectionString")
            ?? DefaultAzuriteConnectionString;

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["CosmosDb:UseEmulator"] = "true",
                    ["CosmosDb:ConnectionString"] = cosmosConnectionString,
                    ["CosmosDb:DatabaseName"] = "CroApp",
                    ["CosmosDb:UsersContainerName"] = "Users",
                    ["CosmosDb:WaypointsContainerName"] = "Waypoints",
                    ["CosmosDb:HubsContainerName"] = "Hubs",
                    ["BlobStorage:ConnectionString"] = blobConnectionString,
                    ["BlobStorage:ProfilePicturesContainerName"] = "profile-pictures",
                    ["BlobStorage:NestPicturesContainerName"] = "nest-pictures",
                    ["Jwt:SigningKey"] = UsersEndpointTests.TestJwtSigningKey,
                    ["Jwt:Issuer"] = "CroApp.Api.Tests",
                    ["Jwt:Audience"] = "CroApp.Api.Tests"
                });
            });
        });

        _client = configuredFactory.CreateClient();
    }

    private async Task<(string UserId, string Token)> RegisterAndLoginAsync(string username, string password)
    {
        var createResponse = await _client.PostAsJsonAsync("/users",
            new { Username = username, Email = $"{username}@example.com", Password = password });
        createResponse.EnsureSuccessStatusCode();
        var created = await createResponse.Content.ReadFromJsonAsync<UserResponseDto>();

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = password });
        loginResponse.EnsureSuccessStatusCode();
        var body = await loginResponse.Content.ReadFromJsonAsync<LoginResponseDto>();
        return (created!.Id, body!.Token);
    }

    private async Task<WaypointDto> CreateWaypointAsync(string token, string name, double lat = 42.0, double lng = -93.5)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/waypoints")
        {
            Content = JsonContent.Create(new { Name = name, Latitude = lat, Longitude = lng })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await _client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private static MultipartFormDataContent BuildUpload(byte[] bytes, string contentType, string fileName = "nest.png")
    {
        var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(bytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        content.Add(fileContent, "file", fileName);
        return content;
    }

    private HttpRequestMessage UploadRequest(string token, string waypointId, byte[] bytes, string contentType, string fileName = "nest.png")
    {
        var request = new HttpRequestMessage(HttpMethod.Put, $"/waypoints/{waypointId}/picture")
        {
            Content = BuildUpload(bytes, contentType, fileName)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    [Fact]
    public async Task Upload_ThenListWaypoints_ReflectsNestPictureUrl()
    {
        var username = $"nestpic-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(token, "Backyard");

        var response = await _client.SendAsync(UploadRequest(token, nest.Id, [1, 2, 3, 4], "image/png"));
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<UploadResponseDto>();
        Assert.False(string.IsNullOrEmpty(body!.ProfilePictureUrl));

        var listRequest = new HttpRequestMessage(HttpMethod.Get, "/waypoints");
        listRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var listResponse = await _client.SendAsync(listRequest);
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();

        var updated = Assert.Single(waypoints!, w => w.Id == nest.Id);
        Assert.Equal(body.ProfilePictureUrl, updated.ProfilePictureUrl);
    }

    [Fact]
    public async Task ListWaypoints_ForNestWithoutItsOwnPicture_FallsBackToOwnersProfilePicture()
    {
        var username = $"nestpic-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(token, "Backyard");

        var profileUploadRequest = new HttpRequestMessage(HttpMethod.Put, "/profile/picture")
        {
            Content = BuildUpload([9, 9, 9], "image/png", "avatar.png")
        };
        profileUploadRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var profileUploadResponse = await _client.SendAsync(profileUploadRequest);
        var profileBody = await profileUploadResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        var listRequest = new HttpRequestMessage(HttpMethod.Get, "/waypoints");
        listRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var listResponse = await _client.SendAsync(listRequest);
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();

        var waypoint = Assert.Single(waypoints!, w => w.Id == nest.Id);
        Assert.Equal(profileBody!.ProfilePictureUrl, waypoint.ProfilePictureUrl);
    }

    [Fact]
    public async Task FriendsWaypoints_PrefersTheNestsOwnPictureOverTheOwnersProfilePicture()
    {
        var usernameA = $"nestpic-user-a-{Guid.NewGuid():N}";
        var usernameB = $"nestpic-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(tokenB, "B's Spot");

        var profileUploadRequest = new HttpRequestMessage(HttpMethod.Put, "/profile/picture")
        {
            Content = BuildUpload([9, 9, 9], "image/png", "avatar.png")
        };
        profileUploadRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);
        await _client.SendAsync(profileUploadRequest);

        var nestUploadResponse = await _client.SendAsync(UploadRequest(tokenB, nest.Id, [1, 2, 3], "image/png"));
        var nestUploadBody = await nestUploadResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        var sendRequest = new HttpRequestMessage(HttpMethod.Post, "/friends/requests")
        {
            Content = JsonContent.Create(new { Username = usernameB })
        };
        sendRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        await _client.SendAsync(sendRequest);

        var acceptRequest = new HttpRequestMessage(HttpMethod.Post, $"/friends/requests/{idA}/accept");
        acceptRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);
        await _client.SendAsync(acceptRequest);

        var getWaypointsRequest = new HttpRequestMessage(HttpMethod.Get, "/friends/waypoints");
        getWaypointsRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        var getWaypointsResponse = await _client.SendAsync(getWaypointsRequest);
        getWaypointsResponse.EnsureSuccessStatusCode();
        var waypoints = await getWaypointsResponse.Content.ReadFromJsonAsync<List<FriendWaypointDto>>();

        var bsNest = Assert.Single(waypoints!, w => w.Id == nest.Id);
        Assert.Equal(nestUploadBody!.ProfilePictureUrl, bsNest.ProfilePictureUrl);
    }

    [Fact]
    public async Task Upload_WithUnsupportedContentType_ReturnsBadRequest()
    {
        var username = $"nestpic-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(token, "Backyard");

        var response = await _client.SendAsync(UploadRequest(token, nest.Id, [1, 2, 3], "application/pdf", "file.pdf"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Upload_TooLarge_ReturnsBadRequest()
    {
        var username = $"nestpic-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(token, "Backyard");

        var response = await _client.SendAsync(UploadRequest(token, nest.Id, new byte[6 * 1024 * 1024], "image/png"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Upload_ForAnotherUsersNest_ReturnsNotFound()
    {
        var usernameA = $"nestpic-user-a-{Guid.NewGuid():N}";
        var usernameB = $"nestpic-user-b-{Guid.NewGuid():N}";
        var (_, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var nest = await CreateWaypointAsync(tokenA, "User A's Spot");

        var response = await _client.SendAsync(UploadRequest(tokenB, nest.Id, [1, 2, 3], "image/png"));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Upload_WithoutToken_ReturnsUnauthorized()
    {
        var request = new HttpRequestMessage(HttpMethod.Put, "/waypoints/some-id/picture")
        {
            Content = BuildUpload([1, 2, 3], "image/png")
        };

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt, string? ProfilePictureUrl);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UploadResponseDto(string ProfilePictureUrl);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, string? ProfilePictureUrl);
    private record FriendWaypointDto(string Id, string UserId, string Username, string? Color, string Name, double Latitude, double Longitude, string? ProfilePictureUrl);
}
