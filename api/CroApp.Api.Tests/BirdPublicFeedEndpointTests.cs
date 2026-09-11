using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

// GET /birds/public is the one bird query in the app that isn't scoped to the caller or
// their friends - see BirdService.ListPublicInTransitAsync. No SpeedMultiplier override
// (same default as BirdSendEndpointTests) since these tests need a bird to still be
// traveling right after send, not resolved instantly.
public class BirdPublicFeedEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public BirdPublicFeedEndpointTests(WebApplicationFactory<Program> factory)
    {
        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build());
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

    private async Task<HubDto> CreateHubAsync(string token, string name, double lat, double lng)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));
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

    private Task<HttpResponseMessage> SendBirdAsync(string token, string birdId, string nestId, string? content = null, bool isPublic = false)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"/birds/{birdId}/send")
        {
            Headers = { Authorization = new AuthenticationHeaderValue("Bearer", token) }
        };
        var form = new MultipartFormDataContent
        {
            { new StringContent(nestId), "nestId" },
            { new StringContent(isPublic.ToString()), "isPublic" },
        };
        if (content is not null)
        {
            form.Add(new StringContent(content), "content");
        }
        request.Content = form;
        return _client.SendAsync(request);
    }

    private Task<HttpResponseMessage> GetNestResidentsAsync(string token, string nestId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{nestId}/birds", token));

    private Task<HttpResponseMessage> GetPublicBirdsAsync(string token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds/public", token));

    // Same "bounce a starter bird home through a same-coordinates Hub" trick
    // BirdSendEndpointTests.LandBirdAtHomeAsync uses - a user only ever gets one personal nest.
    private async Task<(BirdDto Bird, WaypointDto Home, string Token)> LandBirdAtHomeAsync(string usernamePrefix)
    {
        var (_, token) = await RegisterAndLoginAsync($"{usernamePrefix}-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5);

        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var bounceHub = await CreateHubAsync(adminToken, $"Setup Bounce {Guid.NewGuid():N}", 42.0, -93.5);

        var composeResponse = await ComposeBirdAsync(token, "Cro", "Setup Bird", home.Id, bounceHub.Id, content: "setup");
        composeResponse.EnsureSuccessStatusCode();
        var composed = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;

        var backResponse = await SendBirdAsync(token, composed.Id, home.Id);
        backResponse.EnsureSuccessStatusCode();

        var residentsResponse = await GetNestResidentsAsync(token, home.Id);
        residentsResponse.EnsureSuccessStatusCode();
        var residents = await residentsResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        var landed = residents!.Single(b => b.Id == composed.Id);
        Assert.False(landed.IsTraveling);

        return (landed, home, token);
    }

    [Fact]
    public async Task PublicBirds_FromAStranger_AppearWithSenderIdentityAndAClampedPosition()
    {
        var (bird, home, senderToken) = await LandBirdAtHomeAsync("pubfeed-sender");
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var away = await CreateHubAsync(adminToken, $"Away Hub {Guid.NewGuid():N}", 60.0, -93.6);

        var sendResponse = await SendBirdAsync(senderToken, bird.Id, away.Id, "Hello, world", isPublic: true);
        sendResponse.EnsureSuccessStatusCode();

        var (_, viewerToken) = await RegisterAndLoginAsync($"pubfeed-viewer-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var response = await GetPublicBirdsAsync(viewerToken);
        response.EnsureSuccessStatusCode();

        var sightings = await response.Content.ReadFromJsonAsync<List<PublicBirdSightingDto>>();
        var sighting = sightings!.Single(s => s.Id == bird.Id);

        Assert.Equal("Hello, world", sighting.Content);
        Assert.NotNull(sighting.SenderUsername);

        // Clamped away from both real endpoints (home: 42.0,-93.5 / away: 60.0,-93.6) - see
        // BirdService.ListPublicInTransitAsync's PublicSightingFractionRange.
        Assert.InRange(sighting.Latitude, Math.Min(home.Latitude, away.Latitude), Math.Max(home.Latitude, away.Latitude));
        Assert.NotEqual(home.Latitude, sighting.Latitude);
        Assert.NotEqual(away.Latitude, sighting.Latitude);

        // Never leaks the flight's nest ids - a stranger has no way to resolve these to a
        // coordinate anyway (see FriendBird's client-side resolution), but they shouldn't be
        // in the payload at all.
        var raw = await (await GetPublicBirdsAsync(viewerToken)).Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(raw);
        var element = doc.RootElement.EnumerateArray().Single(e => e.GetProperty("id").GetString() == bird.Id);
        Assert.False(element.TryGetProperty("nestFromId", out _));
        Assert.False(element.TryGetProperty("nestToId", out _));
    }

    [Fact]
    public async Task PublicBirds_ExcludesAPrivateBird()
    {
        var (bird, _, senderToken) = await LandBirdAtHomeAsync("pubfeed-private");
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var away = await CreateHubAsync(adminToken, $"Away Hub {Guid.NewGuid():N}", 60.0, -93.6);

        var sendResponse = await SendBirdAsync(senderToken, bird.Id, away.Id, "Shh", isPublic: false);
        sendResponse.EnsureSuccessStatusCode();

        var (_, viewerToken) = await RegisterAndLoginAsync($"pubfeed-viewer-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var response = await GetPublicBirdsAsync(viewerToken);
        response.EnsureSuccessStatusCode();

        var sightings = await response.Content.ReadFromJsonAsync<List<PublicBirdSightingDto>>();
        Assert.DoesNotContain(sightings!, s => s.Id == bird.Id);
    }

    [Fact]
    public async Task PublicBirds_ExcludesTheCallersOwnBird()
    {
        var (bird, _, senderToken) = await LandBirdAtHomeAsync("pubfeed-own");
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var away = await CreateHubAsync(adminToken, $"Away Hub {Guid.NewGuid():N}", 60.0, -93.6);

        var sendResponse = await SendBirdAsync(senderToken, bird.Id, away.Id, "Mine", isPublic: true);
        sendResponse.EnsureSuccessStatusCode();

        var response = await GetPublicBirdsAsync(senderToken);
        response.EnsureSuccessStatusCode();

        var sightings = await response.Content.ReadFromJsonAsync<List<PublicBirdSightingDto>>();
        Assert.DoesNotContain(sightings!, s => s.Id == bird.Id);
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
    private record PublicBirdSightingDto(
        string Id,
        string SenderUserId,
        string SenderUsername,
        string? SenderProfilePictureUrl,
        string Type,
        string? Content,
        string? AudioUrl,
        string? ImageUrl,
        double Latitude,
        double Longitude);
}
