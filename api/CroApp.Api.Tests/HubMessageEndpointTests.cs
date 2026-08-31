using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class HubMessageEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public HubMessageEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:BirdsContainerName"] = "Birds",
                    ["CosmosDb:HubsContainerName"] = "Hubs",
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
                    ["CosmosDb:HubMessagesContainerName"] = "HubMessages",
                    ["CosmosDb:HubReadStatesContainerName"] = "HubReadStates",
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

    private async Task<HubDto> CreateHubAsync(string token, string name, double lat, double lng)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<HubDto>())!;
    }

    private async Task<WaypointDto> CreateWaypointAsync(string token, string name, double lat, double lng, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    // Text-only Cro, so no media upload is needed to satisfy BirdPayloadValidator.
    // isPublic is omitted (server default: false) unless explicitly given.
    private Task<HttpResponseMessage> ComposeBirdAsync(string token, string name, string originNestId, string destinationId, string content, bool? isPublic = null)
    {
        var multipart = new MultipartFormDataContent
        {
            { new StringContent("Cro"), "type" },
            { new StringContent(name), "name" },
            { new StringContent(originNestId), "originNestId" },
            { new StringContent(destinationId), "destinationId" },
            { new StringContent(content), "content" },
        };
        if (isPublic is not null)
        {
            multipart.Add(new StringContent(isPublic.Value.ToString()), "isPublic");
        }
        var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose") { Content = multipart };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return _client.SendAsync(request);
    }

    // Triggers BirdService's lazy arrival resolution for the caller's own birds.
    private Task<HttpResponseMessage> ListOwnBirdsAsync(string token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));

    [Fact]
    public async Task SendingBirdToHub_CanStayPrivate_ButStillAppearsOnBoard()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Test Plaza {Guid.NewGuid():N}", 42.05, -93.55);

        var username = $"hub-poster-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);
        // Same coordinates as the Hub -> zero distance -> instant arrival on the next read.
        var origin = await CreateWaypointAsync(token, "My Nest", 42.05, -93.55);

        var composeResponse = await ComposeBirdAsync(token, "Hello Plaza", origin.Id, hub.Id, "hi everyone", isPublic: false);
        composeResponse.EnsureSuccessStatusCode();

        var listResponse = await ListOwnBirdsAsync(token);
        listResponse.EnsureSuccessStatusCode();
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        var landed = Assert.Single(birds!, b => b.Name == "Hello Plaza");
        Assert.False(landed.IsTraveling);
        Assert.False(landed.IsPublic);

        // A different viewer's live "who's here" view masks it, since it isn't public.
        var viewerUsername = $"hub-viewer-{Guid.NewGuid():N}";
        var (_, viewerToken) = await RegisterAndLoginAsync(viewerUsername, SeedPassword);
        var residentsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/hubs/{hub.Id}/birds", viewerToken));
        residentsResponse.EnsureSuccessStatusCode();
        var residents = await residentsResponse.Content.ReadFromJsonAsync<List<HubResidentBirdDto>>();
        var resident = Assert.Single(residents!, b => b.Name == "Hello Plaza");
        Assert.Null(resident.Content);

        // But the durable board always shows it in full, regardless of IsPublic.
        var messagesResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/hubs/{hub.Id}/messages", token));
        messagesResponse.EnsureSuccessStatusCode();
        var messages = await messagesResponse.Content.ReadFromJsonAsync<List<HubMessageDto>>();
        var posted = Assert.Single(messages!);
        Assert.Equal(username, posted.SenderUsername);
        Assert.Equal("Hello Plaza", posted.BirdName);
        Assert.Equal("My Nest", posted.OriginNestName);
        Assert.Equal("hi everyone", posted.Content);
    }

    [Fact]
    public async Task SendingBirdToHub_RespectsExplicitIsPublicTrue()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Open Plaza {Guid.NewGuid():N}", 42.06, -93.56);

        var username = $"hub-poster-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);
        var origin = await CreateWaypointAsync(token, "My Nest", 42.06, -93.56);

        var composeResponse = await ComposeBirdAsync(token, "Open Bird", origin.Id, hub.Id, "hi everyone", isPublic: true);
        composeResponse.EnsureSuccessStatusCode();

        var listResponse = await ListOwnBirdsAsync(token);
        listResponse.EnsureSuccessStatusCode();
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        var landed = Assert.Single(birds!, b => b.Name == "Open Bird");
        Assert.True(landed.IsPublic);
    }

    [Fact]
    public async Task SendingBirdToFriendNest_DoesNotForcePublic()
    {
        var usernameA = $"friend-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, SeedPassword);
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, SeedPassword);

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var origin = await CreateWaypointAsync(tokenA, "A's Nest", 41.0, -92.0);
        // Same coordinates as the origin -> instant arrival.
        var destination = await CreateWaypointAsync(tokenB, "B's Nest", 41.0, -92.0);

        var composeResponse = await ComposeBirdAsync(tokenA, "Just Us", origin.Id, destination.Id, "private note");
        composeResponse.EnsureSuccessStatusCode();

        var listResponse = await ListOwnBirdsAsync(tokenA);
        listResponse.EnsureSuccessStatusCode();
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        var landed = Assert.Single(birds!, b => b.Name == "Just Us");
        Assert.False(landed.IsTraveling);
        Assert.False(landed.IsPublic);

        _ = idB; // only needed to satisfy the accept call above
    }

    [Fact]
    public async Task GetHubMessages_ForNonexistentHub_ReturnsNotFound()
    {
        var username = $"hub-msg-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs/does-not-exist/messages", token));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetHubMessages_ForHubWithNoMessages_ReturnsEmptyList()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Quiet Corner {Guid.NewGuid():N}", 42.1, -93.6);

        var username = $"hub-msg-viewer-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/hubs/{hub.Id}/messages", token));
        response.EnsureSuccessStatusCode();
        var messages = await response.Content.ReadFromJsonAsync<List<HubMessageDto>>();

        Assert.Empty(messages!);
    }

    [Fact]
    public async Task UnreadCounts_CountsUntilMarkedRead()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Unread Plaza {Guid.NewGuid():N}", 42.2, -93.7);

        var posterUsername = $"hub-unread-poster-{Guid.NewGuid():N}";
        var (_, posterToken) = await RegisterAndLoginAsync(posterUsername, SeedPassword);
        var origin = await CreateWaypointAsync(posterToken, "Poster Nest", 42.2, -93.7);
        (await ComposeBirdAsync(posterToken, "Unread Bird", origin.Id, hub.Id, "hey")).EnsureSuccessStatusCode();
        await ListOwnBirdsAsync(posterToken); // resolves the lazy arrival, same as the board test above

        var viewerUsername = $"hub-unread-viewer-{Guid.NewGuid():N}";
        var (_, viewerToken) = await RegisterAndLoginAsync(viewerUsername, SeedPassword);

        var countsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs/unread-counts", viewerToken));
        countsResponse.EnsureSuccessStatusCode();
        var counts = await countsResponse.Content.ReadFromJsonAsync<Dictionary<string, int>>();
        Assert.Equal(1, counts![hub.Id]);

        var readResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/hubs/{hub.Id}/read", viewerToken));
        readResponse.EnsureSuccessStatusCode();

        var countsAfterResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs/unread-counts", viewerToken));
        countsAfterResponse.EnsureSuccessStatusCode();
        var countsAfter = await countsAfterResponse.Content.ReadFromJsonAsync<Dictionary<string, int>>();
        Assert.Equal(0, countsAfter![hub.Id]);
    }

    [Fact]
    public async Task MarkHubRead_ForNonexistentHub_ReturnsNotFound()
    {
        var username = $"hub-unread-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs/does-not-exist/read", token));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UserResponseDto(string Id, string Username, string Email);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
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
    private record HubResidentBirdDto(
        string Id,
        string UserId,
        string Name,
        string Type,
        string? CurrentNestId,
        bool IsPublic,
        string? Content,
        string? AudioUrl,
        string? ImageUrl);
    private record HubMessageDto(
        string Id,
        string SenderId,
        string SenderUsername,
        string BirdName,
        string? OriginNestName,
        string Type,
        string? Content,
        string? AudioUrl,
        string? ImageUrl,
        DateTimeOffset CreatedAt,
        string? SenderProfilePictureUrl);
}
