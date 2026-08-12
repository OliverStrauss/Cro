using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

// Separate from BirdSendEndpointTests.cs specifically because this class needs a cranked-up
// BirdTravel:SpeedMultiplier so a journey resolves almost instantly - which would make
// BirdSendEndpointTests' "still traveling right after send" assertions (e.g. the
// already-traveling-bird conflict check) unreliable if they shared this config.
public class BirdArrivalEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;

    public BirdArrivalEndpointTests(WebApplicationFactory<Program> factory)
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
                    // Huge multiplier so any test-fixture distance - up to half Earth's
                    // circumference (~20,000km, the max possible) - resolves to a
                    // microsecond-scale flight duration, regardless of which two lat/lngs a
                    // test picks.
                    ["BirdTravel:SpeedMultiplier"] = "1000000000000",
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

    private async Task<WaypointDto> CreateNestAsync(string token, string name, double lat = 42.0, double lng = -93.5)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private async Task<List<BirdDto>> ListBirdsAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<List<BirdDto>>())!;
    }

    private Task<HttpResponseMessage> SendBirdAsync(string? token, string birdId, string nestId, string? content = null) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/send", token, new { NestId = nestId, Content = content }));

    private Task<HttpResponseMessage> GetNestResidentsAsync(string? token, string nestId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{nestId}/birds", token));

    private Task<HttpResponseMessage> MarkReadAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/read", token));

    // Small pause after a send/read write, purely so the emulator's cross-partition query
    // index has caught up with the just-written document before a subsequent GET (a query,
    // not a point read) looks for it - unrelated to flight duration, which the huge
    // SpeedMultiplier already makes effectively instant.
    private static Task WaitForIndexingAsync() => Task.Delay(500);

    [Fact]
    public async Task ArrivedBird_IsVisibleViaNestResidentsEndpoint_MixedWithOwnersOwnBirds()
    {
        var usernameA = $"bird-arrive-a-{Guid.NewGuid():N}";
        var usernameB = $"bird-arrive-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        await ListBirdsAsync(tokenA);
        await ListBirdsAsync(tokenB);
        await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest", 50.0, 50.0);
        var ownBirdB = (await ListBirdsAsync(tokenB))[0];
        var sentBird = (await ListBirdsAsync(tokenA))[0];

        (await SendBirdAsync(tokenA, sentBird.Id, bNest.Id, "For you!")).EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var residentsResponse = await GetNestResidentsAsync(tokenB, bNest.Id);
        residentsResponse.EnsureSuccessStatusCode();
        var residents = await residentsResponse.Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Contains(residents!, b => b.Id == sentBird.Id && !b.IsTraveling && b.CurrentNestId == bNest.Id);
        Assert.Contains(residents!, b => b.Id == ownBirdB.Id);
    }

    [Fact]
    public async Task ArrivedBird_DefaultsToUnread_ThenReadEndpointClearsIt()
    {
        var usernameA = $"bird-read-a-{Guid.NewGuid():N}";
        var usernameB = $"bird-read-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        await ListBirdsAsync(tokenA);
        await ListBirdsAsync(tokenB);
        await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest", 50.0, 50.0);
        var sentBird = (await ListBirdsAsync(tokenA))[0];
        (await SendBirdAsync(tokenA, sentBird.Id, bNest.Id)).EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var beforeRead = await (await GetNestResidentsAsync(tokenB, bNest.Id)).Content.ReadFromJsonAsync<List<BirdDto>>();
        var arrivedBefore = beforeRead!.Single(b => b.Id == sentBird.Id);
        Assert.False(arrivedBefore.IsRead);

        var readResponse = await MarkReadAsync(tokenB, sentBird.Id);
        readResponse.EnsureSuccessStatusCode();

        var afterRead = await (await GetNestResidentsAsync(tokenB, bNest.Id)).Content.ReadFromJsonAsync<List<BirdDto>>();
        var arrivedAfter = afterRead!.Single(b => b.Id == sentBird.Id);
        Assert.True(arrivedAfter.IsRead);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt);
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
        DateTimeOffset UpdatedAt);
}
