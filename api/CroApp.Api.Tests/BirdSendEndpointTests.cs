using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdSendEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section. Used here (as HubEndpointTests.cs
    // already does) to create Hubs for test setup, since a plain user can no longer be given
    // a second nest of their own to bounce a setup bird through (see LandBirdAtHomeAsync).
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public BirdSendEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
                    ["CosmosDb:BirdsContainerName"] = "Birds",
                    // Deliberately left at the real default (1.0, from appsettings.json - not
                    // overridden here) so a just-sent bird reliably stays "traveling" for the
                    // lifetime of these tests (hours/days of simulated flight time). Getting a
                    // bird "landed" for setup instead relies on a zero-distance compose (same
                    // origin/destination coordinates, different nest ids - see
                    // LandBirdAtHomeAsync below), not a cranked multiplier - arrival resolution
                    // itself is covered separately in BirdArrivalEndpointTests.cs, which cranks
                    // the multiplier up instead. A merely-small delta isn't safe here: at Cro's
                    // realistic 60 km/h it's a fraction of a second of real flight time, not
                    // reliably shorter than an HTTP round trip.
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
            new { Name = name, Latitude = lat, Longitude = lng }));
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

    private Task<HttpResponseMessage> SendBirdAsync(string? token, string birdId, string nestId, string? content = null) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/send", token, new { NestId = nestId, Content = content }));

    private Task<HttpResponseMessage> GetNestResidentsAsync(string? token, string nestId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{nestId}/birds", token));

    private Task<HttpResponseMessage> MarkReadAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/read", token));

    // Lands a bird idle at `home` instantly, without needing a cranked SpeedMultiplier (which
    // would make the *real* send-under-test resolve instantly too and defeat "stays
    // traveling" assertions). A user gets exactly one personal nest (see
    // WaypointService.CreateAsync), so the old "compose from a second throwaway nest of this
    // user's own, at the same coordinates, then delete it" trick no longer works - this
    // bounces the setup bird through a same-coordinates Hub instead (reachable to anyone, no
    // ownership needed) and straight back to Home, both hops zero-distance so each resolves
    // the instant it's next queried.
    private async Task<(BirdDto Bird, WaypointDto Home, string UserId, string Token)> LandBirdAtHomeAsync(string usernamePrefix)
    {
        var (userId, token) = await RegisterAndLoginAsync($"{usernamePrefix}-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var home = await CreateNestAsync(token, "Home", 42.0, -93.5, isPublic: false);

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

        return (landed, home, userId, token);
    }

    [Fact]
    public async Task Send_ToAHub_MarksItTravelingWithEta()
    {
        var (bird, home, _, token) = await LandBirdAtHomeAsync("bird-send-user");
        // A user gets exactly one personal nest, so "send to another destination" is
        // exercised against a Hub here rather than a second own nest.
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var away = await CreateHubAsync(adminToken, $"Away Hub {Guid.NewGuid():N}", 60.0, -93.6);

        var response = await SendBirdAsync(token, bird.Id, away.Id, "Hello there");
        response.EnsureSuccessStatusCode();
        var sent = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.True(sent!.IsTraveling);
        Assert.Equal(away.Id, sent.NestToId);
        Assert.Equal(home.Id, sent.NestFromId);
        Assert.Null(sent.CurrentNestId);
        Assert.NotNull(sent.EstimatedArrivalAt);
        Assert.NotNull(sent.DepartedAt);
        Assert.True(sent.EstimatedArrivalAt >= sent.DepartedAt);
        Assert.Equal("Hello there", sent.Content);
    }

    [Fact]
    public async Task Send_AlreadyTravelingBird_ReturnsConflict()
    {
        var (bird, home, _, token) = await LandBirdAtHomeAsync("bird-send-user");
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var away = await CreateHubAsync(adminToken, $"Away Hub {Guid.NewGuid():N}", 60.0, -93.6);

        var first = await SendBirdAsync(token, bird.Id, away.Id);
        first.EnsureSuccessStatusCode();

        var second = await SendBirdAsync(token, bird.Id, home.Id);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task Send_ToBirdsCurrentNest_ReturnsBadRequest()
    {
        var (bird, home, _, token) = await LandBirdAtHomeAsync("bird-send-user");

        var response = await SendBirdAsync(token, bird.Id, home.Id);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Send_ToNestThatIsNeitherOwnNorFriends_ReturnsNotFound()
    {
        var (bird, _, _, tokenA) = await LandBirdAtHomeAsync("bird-send-a");
        var (_, tokenC) = await RegisterAndLoginAsync($"bird-send-c-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var strangersNest = await CreateNestAsync(tokenC, "Stranger's Nest", 10.0, 10.0);

        var response = await SendBirdAsync(tokenA, bird.Id, strangersNest.Id);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Send_ToFriendsNest_Succeeds()
    {
        var (bird, _, idA, tokenA) = await LandBirdAtHomeAsync("bird-friend-a");
        var usernameB = $"bird-friend-b-{Guid.NewGuid():N}";
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var bNest = await CreateNestAsync(tokenB, "B's Nest", 50.0, 50.0);

        var response = await SendBirdAsync(tokenA, bird.Id, bNest.Id, "For you!");
        response.EnsureSuccessStatusCode();
        var sent = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.True(sent!.IsTraveling);
        Assert.Equal(bNest.Id, sent.NestToId);
    }

    [Fact]
    public async Task NestResidents_ForAnotherUsersNest_ReturnsNotFound()
    {
        var (_, tokenA) = await RegisterAndLoginAsync($"bird-nest-a-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync($"bird-nest-b-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var aNest = await CreateNestAsync(tokenA, "A's Nest");

        var response = await GetNestResidentsAsync(tokenB, aNest.Id);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
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
