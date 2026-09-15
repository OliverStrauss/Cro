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
    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section. Used here (as HubEndpointTests.cs
    // already does) to create a Hub for test setup, since a plain user can no longer be given
    // a second nest of their own to compose an "already at my own nest" bird from.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public BirdArrivalEndpointTests(WebApplicationFactory<Program> factory)
    {
        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build());
                // Huge multiplier so any test-fixture distance - up to half Earth's
                // circumference (~20,000km, the max possible) - resolves to a
                // microsecond-scale flight duration, regardless of which two lat/lngs a
                // test picks.
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["BirdTravel:SpeedMultiplier"] = "1000000000000"
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

    private Task<HttpResponseMessage> GetNestResidentsAsync(string? token, string nestId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{nestId}/birds", token));

    private Task<HttpResponseMessage> GetOwnBirdsAsync(string? token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));

    private Task<HttpResponseMessage> GetFriendsAsync(string? token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends", token));

    private Task<HttpResponseMessage> MarkReadAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/read", token));

    private Task<HttpResponseMessage> SendBirdAsync(string? token, string birdId, string nestId, string? content = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"/birds/{birdId}/send");
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
        var form = new MultipartFormDataContent
        {
            { new StringContent(nestId), "nestId" },
        };
        if (content is not null)
        {
            form.Add(new StringContent(content), "content");
        }
        request.Content = form;
        return _client.SendAsync(request);
    }

    private async Task<HubDto> CreateHubAsync(string token, string name, double lat, double lng)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<HubDto>())!;
    }

    // Small pause after a compose/read write, purely so the emulator's cross-partition query
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

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest");

        // A user gets exactly one personal nest (see WaypointService.CreateAsync), so B's own
        // idle bird can no longer be composed from a second nest of B's own - compose it from
        // bNest itself to a same-class-scoped Hub, then bounce it straight back. The huge
        // SpeedMultiplier this test class configures means both hops resolve the instant
        // they're next queried, same as a real cross-user delivery below.
        var bounceHub = await CreateHubAsync(await LoginAsync("Admin 1", SeedPassword), $"B Bounce Hub {Guid.NewGuid():N}", 51.0, 51.0);
        var ownBirdComposeResponse = await ComposeBirdAsync(tokenB, "Cro", "B's Own Bird", bNest.Id, bounceHub.Id, content: "B's own message");
        ownBirdComposeResponse.EnsureSuccessStatusCode();
        var ownBirdComposed = (await ownBirdComposeResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        var bounceBackResponse = await SendBirdAsync(tokenB, ownBirdComposed.Id, bNest.Id);
        bounceBackResponse.EnsureSuccessStatusCode();
        var ownBirdB = (await bounceBackResponse.Content.ReadFromJsonAsync<BirdDto>())!;

        var sentResponse = await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aNest.Id, bNest.Id, content: "For you!");
        sentResponse.EnsureSuccessStatusCode();
        var sentBird = (await sentResponse.Content.ReadFromJsonAsync<BirdDto>())!;

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

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest");

        var sentResponse = await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aNest.Id, bNest.Id, content: "Hi");
        sentResponse.EnsureSuccessStatusCode();
        var sentBird = (await sentResponse.Content.ReadFromJsonAsync<BirdDto>())!;
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

    [Fact]
    public async Task NestResidents_AreOrderedNewestArrivalFirst()
    {
        var usernameA = $"bird-order-a-{Guid.NewGuid():N}";
        var usernameB = $"bird-order-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest");

        var firstResponse = await ComposeBirdAsync(tokenA, "Cro", "First Bird", aNest.Id, bNest.Id, content: "First");
        firstResponse.EnsureSuccessStatusCode();
        var firstBird = (await firstResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        await WaitForIndexingAsync();
        // Resolves the first bird's arrival (setting its UpdatedAt) strictly before the
        // second bird is even composed, so the two arrival timestamps can't tie.
        await GetNestResidentsAsync(tokenB, bNest.Id);

        var secondResponse = await ComposeBirdAsync(tokenA, "Cro", "Second Bird", aNest.Id, bNest.Id, content: "Second");
        secondResponse.EnsureSuccessStatusCode();
        var secondBird = (await secondResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        await WaitForIndexingAsync();

        var residents = await (await GetNestResidentsAsync(tokenB, bNest.Id)).Content.ReadFromJsonAsync<List<BirdDto>>();

        var firstIndex = residents!.FindIndex(b => b.Id == firstBird.Id);
        var secondIndex = residents.FindIndex(b => b.Id == secondBird.Id);
        Assert.True(secondIndex >= 0 && firstIndex >= 0 && secondIndex < firstIndex,
            "the more recently arrived bird should be listed before the earlier one");
    }

    [Fact]
    public async Task BirdArrival_AtFriendsNest_IncrementsBothSidesExchangeCount()
    {
        var usernameA = $"exch-a-{Guid.NewGuid():N}";
        var usernameB = $"exch-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest");

        var sentResponse = await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aNest.Id, bNest.Id, content: "Hi");
        sentResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();

        // GET /friends never touches birds itself - the arrival (and the exchange-count
        // bump alongside it, see ResolveArrivalIfDueAsync) is only ever resolved lazily by
        // some query that touches the bird, same as every other arrival test in this file.
        (await GetNestResidentsAsync(tokenB, bNest.Id)).EnsureSuccessStatusCode();

        var friendsForAResponse = await GetFriendsAsync(tokenA);
        friendsForAResponse.EnsureSuccessStatusCode();
        var friendsForA = await friendsForAResponse.Content.ReadFromJsonAsync<List<FriendDto>>();

        var friendsForBResponse = await GetFriendsAsync(tokenB);
        friendsForBResponse.EnsureSuccessStatusCode();
        var friendsForB = await friendsForBResponse.Content.ReadFromJsonAsync<List<FriendDto>>();

        Assert.Equal(1, friendsForA!.Single(f => f.Id == idB).ExchangeCount);
        Assert.Equal(1, friendsForB!.Single(f => f.Id == idA).ExchangeCount);
    }

    [Fact]
    public async Task BirdArrival_AtOwnNestOrHub_DoesNotIncrementAnyExchangeCount()
    {
        var usernameA = $"exch-own-a-{Guid.NewGuid():N}";
        var usernameB = $"exch-own-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var aNest = await CreateNestAsync(tokenA, "A's Nest");
        var bounceHub = await CreateHubAsync(await LoginAsync("Admin 1", SeedPassword), $"Exch Bounce Hub {Guid.NewGuid():N}", 52.0, 52.0);

        // A's own bird, sent to a Hub then bounced back to A's own nest - neither leg ever
        // lands at a friend's nest, so B's exchange count with A must stay untouched
        // throughout, and A's own count for B must never move either.
        var composeResponse = await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aNest.Id, bounceHub.Id, content: "To hub");
        composeResponse.EnsureSuccessStatusCode();
        var composed = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        await WaitForIndexingAsync();
        (await GetOwnBirdsAsync(tokenA)).EnsureSuccessStatusCode();

        var bounceBackResponse = await SendBirdAsync(tokenA, composed.Id, aNest.Id);
        bounceBackResponse.EnsureSuccessStatusCode();
        await WaitForIndexingAsync();
        (await GetOwnBirdsAsync(tokenA)).EnsureSuccessStatusCode();

        var friendsForAResponse = await GetFriendsAsync(tokenA);
        friendsForAResponse.EnsureSuccessStatusCode();
        var friendsForA = await friendsForAResponse.Content.ReadFromJsonAsync<List<FriendDto>>();

        var friendsForBResponse = await GetFriendsAsync(tokenB);
        friendsForBResponse.EnsureSuccessStatusCode();
        var friendsForB = await friendsForBResponse.Content.ReadFromJsonAsync<List<FriendDto>>();

        Assert.Equal(0, friendsForA!.Single(f => f.Id == idB).ExchangeCount);
        Assert.Equal(0, friendsForB!.Single(f => f.Id == idA).ExchangeCount);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
    private record FriendDto(string Id, string Username, string? Color, string? ProfilePictureUrl, bool IsAdmin, int ExchangeCount);
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
