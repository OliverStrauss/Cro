using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

// Cranks BirdTravel:SpeedMultiplier the same way BirdArrivalEndpointTests.cs does, so a
// composed bird's journey resolves almost instantly and arrival-time event recording
// (BirdArrived/BirdArrivedAtYourNest/HubPostCreated) can be exercised without a real wait.
public class EventEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public EventEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:EventsContainerName"] = "Events",
                    // Same huge multiplier as BirdArrivalEndpointTests.cs, for the same
                    // reason - any test-fixture distance resolves to a microsecond-scale
                    // flight duration.
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

        var token = await LoginAsync(username, password);
        return (created!.Id, token);
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

    private Task<HttpResponseMessage> CreateHubAsync(string token, string name, double lat = 45.0, double lng = -90.0) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token, new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));

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

    private async Task<List<EventDto>> GetEventsAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/events", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<List<EventDto>>())!;
    }

    private async Task<List<EventDto>> GetNotificationsAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/notifications", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<List<EventDto>>())!;
    }

    private async Task<int> GetUnreadCountAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/notifications/unread-count", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<UnreadCountDto>())!.Count;
    }

    // Small pause after a write, purely so the emulator's cross-partition/partition-scoped
    // query index has caught up before a subsequent GET looks for it - same convention as
    // BirdArrivalEndpointTests.cs's WaitForIndexingAsync.
    private static Task WaitForIndexingAsync() => Task.Delay(500);

    [Fact]
    public async Task ComposeBird_RecordsDepartedAndJoinedFlockEvents()
    {
        var username = $"event-compose-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var origin = await CreateNestAsync(token, "Origin Roost");
        // A user gets exactly one personal nest, so the compose destination here is a Hub
        // rather than a second nest of the same user's own.
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var destinationHubResponse = await CreateHubAsync(adminToken, $"Second Roost {Guid.NewGuid():N}", 43.0, -94.0);
        destinationHubResponse.EnsureSuccessStatusCode();
        var destination = (await destinationHubResponse.Content.ReadFromJsonAsync<HubDto>())!;

        var composeResponse = await ComposeBirdAsync(token, "Cro", "Percy", origin.Id, destination.Id, content: "Hello");
        composeResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var events = await GetEventsAsync(token);
        Assert.Contains(events, e => e.Kind == "BirdDeparted" && e.DisplayText.Contains("Percy") && e.DisplayText.Contains("Origin Roost") && e.DisplayText.Contains("Second Roost"));
        Assert.Contains(events, e => e.Kind == "BirdJoinedFlock" && e.DisplayText.Contains("Percy"));
        Assert.All(events, e => Assert.False(e.IsNotification && (e.Kind == "BirdDeparted" || e.Kind == "BirdJoinedFlock")));
    }

    [Fact]
    public async Task BirdArrival_RecordsArrivedForSender_AndArrivedAtYourNestNotificationForOwner()
    {
        var usernameA = $"event-arrive-a-{Guid.NewGuid():N}";
        var usernameB = $"event-arrive-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest", 50.0, -90.0);

        var sentResponse = await ComposeBirdAsync(tokenA, "Cro", "Juniper", aNest.Id, bNest.Id, content: "For you!");
        sentResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        // Triggers BirdService.ResolveArrivalIfDueAsync on B's side regardless of the bird's
        // own owner (A) - GetNestResidentsAsync resolves arrival for every candidate at the
        // nest, not just ones the caller owns.
        var residentsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{bNest.Id}/birds", tokenB));
        residentsResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var senderEvents = await GetEventsAsync(tokenA);
        Assert.Contains(senderEvents, e => e.Kind == "BirdArrived" && e.DisplayText.Contains("Juniper"));

        var ownerEvents = await GetEventsAsync(tokenB);
        Assert.Contains(ownerEvents, e => e.Kind == "BirdArrivedAtYourNest" && e.DisplayText.Contains("Juniper") && e.TargetType == "Nest" && e.TargetId == bNest.Id);

        var ownerNotifications = await GetNotificationsAsync(tokenB);
        var notification = Assert.Single(ownerNotifications, n => n.Kind == "BirdArrivedAtYourNest");
        Assert.False(notification.IsRead);
    }

    [Fact]
    public async Task BirdLandingAtHub_RecordsHubPostCreatedEvent()
    {
        var username = $"event-hub-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var adminToken = await LoginAsync("Admin 1", SeedPassword);

        var hubResponse = await CreateHubAsync(adminToken, $"Lighthouse {Guid.NewGuid():N}");
        hubResponse.EnsureSuccessStatusCode();
        var hub = (await hubResponse.Content.ReadFromJsonAsync<HubDto>())!;

        var origin = await CreateNestAsync(token, "Home Roost");
        var composeResponse = await ComposeBirdAsync(token, "Cro", "Fen", origin.Id, hub.Id, content: "Landmark note");
        composeResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        // Triggers ResolveArrivalIfDueAsync for the sender's own bird.
        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));
        listResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var events = await GetEventsAsync(token);
        Assert.Contains(events, e => e.Kind == "HubPostCreated" && e.DisplayText.Contains("Fen") && e.TargetType == "Hub" && e.TargetId == hub.Id);
        Assert.Contains(events, e => e.Kind == "BirdArrived" && e.DisplayText.Contains("Fen"));
        Assert.DoesNotContain(events, e => e.Kind == "BirdArrivedAtYourNest");
    }

    [Fact]
    public async Task AcceptFriendRequest_RecordsEventsForBothSides()
    {
        var usernameA = $"event-friend-a-{Guid.NewGuid():N}";
        var usernameB = $"event-friend-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        var acceptResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));
        acceptResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var acceptorEvents = await GetEventsAsync(tokenB);
        Assert.Contains(acceptorEvents, e => e.Kind == "FriendAdded" && !e.IsNotification && e.DisplayText.Contains(usernameA));

        var requesterEvents = await GetEventsAsync(tokenA);
        Assert.Contains(requesterEvents, e => e.Kind == "FriendRequestAccepted" && e.DisplayText.Contains(usernameB));

        var requesterNotifications = await GetNotificationsAsync(tokenA);
        Assert.Contains(requesterNotifications, n => n.Kind == "FriendRequestAccepted" && !n.IsRead);
    }

    [Fact]
    public async Task MarkNotificationRead_AndMarkAllRead_ClearUnreadCount()
    {
        var usernameA = $"event-read-a-{Guid.NewGuid():N}";
        var usernameB = $"event-read-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));
        await WaitForIndexingAsync();

        Assert.True(await GetUnreadCountAsync(tokenA) >= 1);
        var notification = (await GetNotificationsAsync(tokenA)).First(n => n.Kind == "FriendRequestAccepted");

        var readResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/notifications/{notification.Id}/read", tokenA));
        readResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();
        Assert.Equal(0, await GetUnreadCountAsync(tokenA));

        // A second request/accept produces a fresh unread notification for read-all to clear.
        var usernameC = $"event-read-c-{Guid.NewGuid():N}";
        var (idC, tokenC) = await RegisterAndLoginAsync(usernameC, "correct-horse-battery-staple");
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameC }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenC));
        await WaitForIndexingAsync();
        Assert.True(await GetUnreadCountAsync(tokenA) >= 1);

        var readAllResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/notifications/read-all", tokenA));
        readAllResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();
        Assert.Equal(0, await GetUnreadCountAsync(tokenA));
    }

    [Fact]
    public async Task Events_AreIsolatedPerUser()
    {
        var usernameA = $"event-isolate-a-{Guid.NewGuid():N}";
        var usernameB = $"event-isolate-b-{Guid.NewGuid():N}";
        var (_, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var origin = await CreateNestAsync(tokenA, "Isolated Origin");
        // A user gets exactly one personal nest, so the compose destination here is a Hub
        // rather than a second nest of the same user's own.
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var destinationHubResponse = await CreateHubAsync(adminToken, $"Isolated Destination {Guid.NewGuid():N}", 40.0, -95.0);
        destinationHubResponse.EnsureSuccessStatusCode();
        var destination = (await destinationHubResponse.Content.ReadFromJsonAsync<HubDto>())!;
        var uniqueBirdName = $"Unique-{Guid.NewGuid():N}";
        (await ComposeBirdAsync(tokenA, "Cro", uniqueBirdName, origin.Id, destination.Id, content: "hi")).EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        var bEvents = await GetEventsAsync(tokenB);
        Assert.DoesNotContain(bEvents, e => e.DisplayText.Contains(uniqueBirdName));
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
    private record UnreadCountDto(int Count);
    private record EventDto(
        string Id,
        string UserId,
        string Kind,
        string DisplayText,
        string? QuotedNote,
        string? TargetType,
        string? TargetId,
        bool IsNotification,
        bool IsRead,
        DateTimeOffset CreatedAt);
}
