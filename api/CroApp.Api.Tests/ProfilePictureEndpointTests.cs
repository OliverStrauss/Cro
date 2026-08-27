using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class ProfilePictureEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    private const string DefaultAzuriteConnectionString = "UseDevelopmentStorage=true";

    private readonly HttpClient _client;

    public ProfilePictureEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
                    ["BlobStorage:ConnectionString"] = blobConnectionString,
                    ["BlobStorage:ProfilePicturesContainerName"] = "profile-pictures",
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

    private static MultipartFormDataContent BuildUpload(byte[] bytes, string contentType, string fileName = "avatar.png")
    {
        var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(bytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        content.Add(fileContent, "file", fileName);
        return content;
    }

    private HttpRequestMessage UploadRequest(string token, byte[] bytes, string contentType, string fileName = "avatar.png")
    {
        var request = new HttpRequestMessage(HttpMethod.Put, "/profile/picture")
        {
            Content = BuildUpload(bytes, contentType, fileName)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    [Fact]
    public async Task Upload_ThenGetUser_ReflectsProfilePictureUrl()
    {
        var username = $"pfp-user-{Guid.NewGuid():N}";
        var (userId, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(UploadRequest(token, [1, 2, 3, 4], "image/png"));
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<UploadResponseDto>();
        Assert.False(string.IsNullOrEmpty(body!.ProfilePictureUrl));

        var getResponse = await _client.GetAsync($"/users/{userId}");
        getResponse.EnsureSuccessStatusCode();
        var user = await getResponse.Content.ReadFromJsonAsync<UserResponseDto>();
        Assert.Equal(body.ProfilePictureUrl, user!.ProfilePictureUrl);
    }

    [Fact]
    public async Task Reupload_OverwritesRatherThanCreatingASecondBlob()
    {
        var username = $"pfp-user-{Guid.NewGuid():N}";
        var (userId, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var firstResponse = await _client.SendAsync(UploadRequest(token, [1, 2, 3], "image/png"));
        var firstBody = await firstResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        var secondResponse = await _client.SendAsync(UploadRequest(token, [4, 5, 6, 7], "image/png"));
        var secondBody = await secondResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        Assert.Equal(firstBody!.ProfilePictureUrl, secondBody!.ProfilePictureUrl);

        var getResponse = await _client.GetAsync($"/users/{userId}");
        var user = await getResponse.Content.ReadFromJsonAsync<UserResponseDto>();
        Assert.Equal(secondBody.ProfilePictureUrl, user!.ProfilePictureUrl);
    }

    [Fact]
    public async Task Upload_WithUnsupportedContentType_ReturnsBadRequest()
    {
        var username = $"pfp-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(UploadRequest(token, [1, 2, 3], "application/pdf", "file.pdf"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Upload_TooLarge_ReturnsBadRequest()
    {
        var username = $"pfp-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(UploadRequest(token, new byte[6 * 1024 * 1024], "image/png"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Upload_WithoutToken_ReturnsUnauthorized()
    {
        var request = new HttpRequestMessage(HttpMethod.Put, "/profile/picture")
        {
            Content = BuildUpload([1, 2, 3], "image/png")
        };

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetFriends_IncludesProfilePictureUrl()
    {
        var usernameA = $"pfp-user-a-{Guid.NewGuid():N}";
        var usernameB = $"pfp-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var uploadResponse = await _client.SendAsync(UploadRequest(tokenB, [1, 2, 3], "image/png"));
        var uploadBody = await uploadResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        var sendRequest = new HttpRequestMessage(HttpMethod.Post, "/friends/requests")
        {
            Content = JsonContent.Create(new { Username = usernameB })
        };
        sendRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        await _client.SendAsync(sendRequest);

        var acceptRequest = new HttpRequestMessage(HttpMethod.Post, $"/friends/requests/{idA}/accept");
        acceptRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);
        await _client.SendAsync(acceptRequest);

        var getFriendsRequest = new HttpRequestMessage(HttpMethod.Get, "/friends");
        getFriendsRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        var getFriendsResponse = await _client.SendAsync(getFriendsRequest);
        getFriendsResponse.EnsureSuccessStatusCode();
        var friends = await getFriendsResponse.Content.ReadFromJsonAsync<List<FriendDto>>();

        var bAsSeenByA = Assert.Single(friends!, f => f.Id == idB);
        Assert.Equal(uploadBody!.ProfilePictureUrl, bAsSeenByA.ProfilePictureUrl);
    }

    [Fact]
    public async Task GetFriendsWaypoints_IncludesProfilePictureUrlAndWaypointName()
    {
        var usernameA = $"pfp-user-a-{Guid.NewGuid():N}";
        var usernameB = $"pfp-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var uploadResponse = await _client.SendAsync(UploadRequest(tokenB, [1, 2, 3], "image/png"));
        var uploadBody = await uploadResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        var sendRequest = new HttpRequestMessage(HttpMethod.Post, "/friends/requests")
        {
            Content = JsonContent.Create(new { Username = usernameB })
        };
        sendRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        await _client.SendAsync(sendRequest);

        var acceptRequest = new HttpRequestMessage(HttpMethod.Post, $"/friends/requests/{idA}/accept");
        acceptRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);
        await _client.SendAsync(acceptRequest);

        var setWaypointRequest = new HttpRequestMessage(HttpMethod.Post, "/waypoints")
        {
            Content = JsonContent.Create(new { Name = "B's Spot", Latitude = 10.0, Longitude = 20.0 })
        };
        setWaypointRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);
        await _client.SendAsync(setWaypointRequest);

        var getWaypointsRequest = new HttpRequestMessage(HttpMethod.Get, "/friends/waypoints");
        getWaypointsRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);
        var getWaypointsResponse = await _client.SendAsync(getWaypointsRequest);
        getWaypointsResponse.EnsureSuccessStatusCode();
        var waypoints = await getWaypointsResponse.Content.ReadFromJsonAsync<List<FriendWaypointDto>>();

        var bAsSeenByA = Assert.Single(waypoints!, w => w.UserId == idB);
        Assert.Equal(uploadBody!.ProfilePictureUrl, bAsSeenByA.ProfilePictureUrl);
        Assert.Equal("B's Spot", bAsSeenByA.Name);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt, string? ProfilePictureUrl);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UploadResponseDto(string ProfilePictureUrl);
    private record FriendDto(string Id, string Username, string? Color, string? ProfilePictureUrl);
    private record FriendWaypointDto(string Id, string UserId, string Username, string? Color, string Name, double Latitude, double Longitude, string? ProfilePictureUrl);
}
