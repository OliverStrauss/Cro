using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public BirdEndpointTests(WebApplicationFactory<Program> factory)
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

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section. Used here to create a Hub for
    // test setup, since a plain user can no longer be given a second nest of their own to
    // act as a compose destination.
    private const string SeedPassword = "correct-horse-battery-staple";

    private async Task<string> RegisterAndLoginAsync(string username, string password)
    {
        var createResponse = await _client.PostAsJsonAsync("/users",
            new { Username = username, Email = $"{username}@example.com", Password = password });
        createResponse.EnsureSuccessStatusCode();

        return await LoginAsync(username, password);
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

    private Task<HttpResponseMessage> ListBirdsAsync(string? token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));

    private async Task<WaypointDto> CreateWaypointAsync(string token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private async Task<HubDto> CreateHubAsync(string adminToken, string name, double lat, double lng)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", adminToken,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<HubDto>())!;
    }

    private Task<HttpResponseMessage> ComposeBirdAsync(
        string? token,
        string type,
        string name,
        string originNestId,
        string destinationId,
        string? content = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose");
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
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

    [Fact]
    public async Task ListBirds_ForNewUser_ReturnsStarterRoster()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await ListBirdsAsync(token);
        response.EnsureSuccessStatusCode();
        var birds = await response.Content.ReadFromJsonAsync<List<BirdDto>>();

        // A new user is auto-provisioned the fixed starter roster (see
        // BirdTypeCatalog.StarterRoster), not zero birds - spawning is gone.
        Assert.Equal(5, birds!.Count);
    }

    [Fact]
    public async Task ListBirds_WithoutToken_ReturnsUnauthorized()
    {
        var response = await ListBirdsAsync(token: null);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Birds_AreScopedToTheAuthenticatedUser()
    {
        var usernameA = $"bird-user-a-{Guid.NewGuid():N}";
        var usernameB = $"bird-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var tokenB = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var aOrigin = await CreateWaypointAsync(tokenA, "A's Nest", isPublic: false);
        // A user gets exactly one personal nest, so the compose destination here is a Hub
        // rather than a second nest of tokenA's own.
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var aDest = await CreateHubAsync(adminToken, $"A's Away Hub {Guid.NewGuid():N}", 43.0, -94.0);
        (await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aOrigin.Id, aDest.Id, content: "hi")).EnsureSuccessStatusCode();

        var birdsA = await (await ListBirdsAsync(tokenA)).Content.ReadFromJsonAsync<List<BirdDto>>();
        var birdsB = await (await ListBirdsAsync(tokenB)).Content.ReadFromJsonAsync<List<BirdDto>>();

        // Each user's starter roster (5 birds) plus A's composed bird - scoping is what's
        // under test here, not the roster count.
        Assert.Contains(birdsA!, b => b.Name == "A's Bird");
        Assert.DoesNotContain(birdsB!, b => b.Name == "A's Bird");
        Assert.Equal(5, birdsB!.Count);
    }

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
