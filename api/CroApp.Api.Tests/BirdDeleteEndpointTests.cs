using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdDeleteEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public BirdDeleteEndpointTests(WebApplicationFactory<Program> factory)
    {
        var connectionString = Environment.GetEnvironmentVariable("CosmosDb__ConnectionString")
            ?? DefaultEmulatorConnectionString;

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["CosmosDb:UseEmulator"] = "true",
                    ["CosmosDb:ConnectionString"] = connectionString,
                    ["CosmosDb:DatabaseName"] = "CroApp",
                    ["CosmosDb:UsersContainerName"] = "Users",
                    ["CosmosDb:WaypointsContainerName"] = "Waypoints",
                    ["CosmosDb:HubsContainerName"] = "Hubs",
                    ["CosmosDb:BirdsContainerName"] = "Birds",
                    // Left at the real default so a genuinely far send (used only by the
                    // still-traveling test) reliably stays in flight for the test's lifetime -
                    // every other test here lands a bird via a near-zero-distance compose
                    // instead of a cranked multiplier.
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

        return (created!.Id, await LoginAsync(username, password));
    }

    private async Task<string> LoginAsync(string username, string password)
    {
        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = password });
        loginResponse.EnsureSuccessStatusCode();
        var body = await loginResponse.Content.ReadFromJsonAsync<LoginResponseDto>();
        return body!.Token;
    }

    private static HttpRequestMessage AuthedRequest(HttpMethod method, string uri, string? token, object? body = null)
    {
        var request = new HttpRequestMessage(method, uri);
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
        return request;
    }

    private async Task<WaypointDto> CreateNestAsync(string token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private async Task<HubDto> CreateHubAsync(string adminToken, string name, double lat, double lng)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", adminToken,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Pub" }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<HubDto>())!;
    }

    private Task<HttpResponseMessage> ComposeBirdAsync(
        string token, string type, string name, string originNestId, string destinationId, string? content = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose")
        {
            Headers = { Authorization = new AuthenticationHeaderValue("Bearer", token) }
        };
        var form = new MultipartFormDataContent
        {
            { new StringContent(type), "type" },
            { new StringContent(name), "name" },
            { new StringContent(originNestId), "originNestId" },
            { new StringContent(destinationId), "destinationId" },
        };
        if (content is not null)
        {
            form.Add(new StringContent(content), "content");
        }
        request.Content = form;
        return _client.SendAsync(request);
    }

    // Composes a bird then immediately lists the caller's own birds - which resolves
    // arrival as a side effect regardless of which nest (own, a friend's, or a Hub) it
    // currently sits at, since a bird's owner never changes, only its CurrentNestId.
    private async Task<BirdDto> ComposeAndLandAsync(string composerToken, string originId, string destinationId)
    {
        var composeResponse = await ComposeBirdAsync(composerToken, "Cro", "Setup Bird", originId, destinationId, content: "hi");
        composeResponse.EnsureSuccessStatusCode();
        var composed = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", composerToken));
        listResponse.EnsureSuccessStatusCode();
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        return birds!.Single(b => b.Id == composed.Id);
    }

    private Task<HttpResponseMessage> DeleteBirdAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/birds/{birdId}", token));

    [Fact]
    public async Task DeleteBird_WhileIdleAtPrivateNest_Succeeds()
    {
        var (_, token) = await RegisterAndLoginAsync($"delete-user-{Guid.NewGuid():N}", SeedPassword);
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5, isPublic: false);
        var setupOrigin = await CreateNestAsync(token, "Setup", 42.0001, -93.5001, isPublic: true);
        var bird = await ComposeAndLandAsync(token, setupOrigin.Id, home.Id);
        Assert.False(bird.IsTraveling);
        Assert.Equal(home.Id, bird.CurrentNestId);

        var response = await DeleteBirdAsync(token, bird.Id);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        Assert.DoesNotContain(birds!, b => b.Id == bird.Id);
    }

    [Fact]
    public async Task DeleteBird_WhileTraveling_ReturnsConflict()
    {
        var (_, token) = await RegisterAndLoginAsync($"delete-user-{Guid.NewGuid():N}", SeedPassword);
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5, isPublic: false);
        var away = await CreateNestAsync(token, "Away", 60.0, -93.6, isPublic: true); // genuinely far - stays in flight

        var composeResponse = await ComposeBirdAsync(token, "Cro", "In Flight", home.Id, away.Id, content: "hi");
        composeResponse.EnsureSuccessStatusCode();
        var bird = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        Assert.True(bird.IsTraveling);

        var response = await DeleteBirdAsync(token, bird.Id);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task DeleteBird_WhileAtPublicNest_ReturnsConflict()
    {
        var (_, token) = await RegisterAndLoginAsync($"delete-user-{Guid.NewGuid():N}", SeedPassword);
        var setupOrigin = await CreateNestAsync(token, "Setup", 42.0, -93.5, isPublic: false);
        var pub = await CreateNestAsync(token, "Public Spot", 42.0001, -93.5001, isPublic: true);
        var bird = await ComposeAndLandAsync(token, setupOrigin.Id, pub.Id);
        Assert.False(bird.IsTraveling);
        Assert.Equal(pub.Id, bird.CurrentNestId);

        var response = await DeleteBirdAsync(token, bird.Id);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task DeleteBird_WhileAtFriendsNest_ReturnsConflict()
    {
        var usernameA = $"delete-a-{Guid.NewGuid():N}";
        var usernameB = $"delete-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, SeedPassword);
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, SeedPassword);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var aHome = await CreateNestAsync(tokenA, "A's Home", 42.0, -93.5, isPublic: false);
        var bNest = await CreateNestAsync(tokenB, "B's Nest", 42.0001, -93.5001, isPublic: false);

        var bird = await ComposeAndLandAsync(tokenA, aHome.Id, bNest.Id);
        Assert.False(bird.IsTraveling);
        Assert.Equal(bNest.Id, bird.CurrentNestId);

        var response = await DeleteBirdAsync(tokenA, bird.Id);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task DeleteBird_WhileAtHub_ReturnsConflict()
    {
        var (_, token) = await RegisterAndLoginAsync($"delete-user-{Guid.NewGuid():N}", SeedPassword);
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5, isPublic: false);

        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Test Hub {Guid.NewGuid():N}", 42.0001, -93.5001);

        var bird = await ComposeAndLandAsync(token, home.Id, hub.Id);
        Assert.False(bird.IsTraveling);
        Assert.Equal(hub.Id, bird.CurrentNestId);

        var response = await DeleteBirdAsync(token, bird.Id);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task DeleteBird_ForAnotherUsersBird_ReturnsNotFound()
    {
        var (_, tokenA) = await RegisterAndLoginAsync($"delete-a-{Guid.NewGuid():N}", SeedPassword);
        var (_, tokenB) = await RegisterAndLoginAsync($"delete-b-{Guid.NewGuid():N}", SeedPassword);
        var home = await CreateNestAsync(tokenA, "Home", 42.0, -93.5, isPublic: false);
        var setupOrigin = await CreateNestAsync(tokenA, "Setup", 42.0001, -93.5001, isPublic: true);
        var bird = await ComposeAndLandAsync(tokenA, setupOrigin.Id, home.Id);

        var response = await DeleteBirdAsync(tokenB, bird.Id);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteBird_WithoutToken_ReturnsUnauthorized()
    {
        var response = await DeleteBirdAsync(null, "some-id");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task DeletingABird_FreesACapSlot()
    {
        var (_, token) = await RegisterAndLoginAsync($"delete-user-{Guid.NewGuid():N}", SeedPassword);
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5, isPublic: false);
        var away = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        // Four genuinely in-flight birds (far distance, stay traveling for the test's
        // lifetime) plus one landed-at-home bird (near-zero distance) fill the 5-bird cap.
        for (var i = 0; i < 4; i++)
        {
            (await ComposeBirdAsync(token, "Cro", $"Bird {i}", home.Id, away.Id, content: "hi")).EnsureSuccessStatusCode();
        }
        var landed = await ComposeAndLandAsync(token, away.Id, home.Id);
        Assert.False(landed.IsTraveling);

        var sixth = await ComposeBirdAsync(token, "Cro", "One Too Many", home.Id, away.Id, content: "hi");
        Assert.Equal(HttpStatusCode.Conflict, sixth.StatusCode);

        (await DeleteBirdAsync(token, landed.Id)).EnsureSuccessStatusCode();

        var afterDelete = await ComposeBirdAsync(token, "Cro", "Room Again", home.Id, away.Id, content: "hi");
        Assert.Equal(HttpStatusCode.Created, afterDelete.StatusCode);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
    private record BirdDto(
        string Id,
        string UserId,
        string Name,
        string? CurrentNestId,
        bool IsTraveling,
        string? NestFromId,
        string? NestToId,
        double? Speed,
        string? Content,
        string Type,
        DateTimeOffset? DepartedAt,
        DateTimeOffset? EstimatedArrivalAt,
        bool IsRead,
        DateTimeOffset UpdatedAt,
        string? AudioUrl,
        string? ImageUrl,
        string? ProfilePictureUrl,
        bool IsPublic);
}
