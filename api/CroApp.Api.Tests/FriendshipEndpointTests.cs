using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class FriendshipEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;

    public FriendshipEndpointTests(WebApplicationFactory<Program> factory)
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

    private async Task SendRequestAsync(string token, string targetUsername)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", token,
            new { Username = targetUsername }));
        response.EnsureSuccessStatusCode();
    }

    private async Task<List<FriendDto>> GetFriendsAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<List<FriendDto>>())!;
    }

    [Fact]
    public async Task SendRequest_MakesItVisibleAsIncomingAndOutgoing()
    {
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync($"friend-user-a-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);

        var outgoingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/requests/outgoing", tokenA));
        outgoingResponse.EnsureSuccessStatusCode();
        var outgoing = await outgoingResponse.Content.ReadFromJsonAsync<List<FriendRequestDto>>();
        Assert.Contains(outgoing!, r => r.Id == idB);

        var incomingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/requests/incoming", tokenB));
        incomingResponse.EnsureSuccessStatusCode();
        var incoming = await incomingResponse.Content.ReadFromJsonAsync<List<FriendRequestDto>>();
        Assert.Contains(incoming!, r => r.Id == idA);
    }

    [Fact]
    public async Task Accept_MakesBothSidesFriendsWithIndependentColors()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);

        var acceptResponse = await _client.SendAsync(
            AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));
        acceptResponse.EnsureSuccessStatusCode();

        var friendsOfA = await GetFriendsAsync(tokenA);
        var friendsOfB = await GetFriendsAsync(tokenB);

        var bAsSeenByA = Assert.Single(friendsOfA, f => f.Id == idB);
        var aAsSeenByB = Assert.Single(friendsOfB, f => f.Id == idA);

        Assert.NotNull(bAsSeenByA.Color);
        Assert.NotNull(aAsSeenByB.Color);
    }

    [Fact]
    public async Task SendRequest_Duplicate_ReturnsConflict()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (_, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA,
            new { Username = usernameB }));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task SendRequest_ToSelf_ReturnsBadRequest()
    {
        var username = $"friend-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", token,
            new { Username = username }));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SendRequest_ToUnknownUsername_ReturnsNotFound()
    {
        var username = $"friend-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", token,
            new { Username = $"no-such-user-{Guid.NewGuid():N}" }));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Accept_WithNoPendingRequest_ReturnsBadRequest()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, _) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var response = await _client.SendAsync(
            AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task FriendEndpoints_WithoutToken_ReturnUnauthorized()
    {
        var getFriends = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends", token: null));
        var sendRequest = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", token: null,
            new { Username = "someone" }));

        Assert.Equal(HttpStatusCode.Unauthorized, getFriends.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, sendRequest.StatusCode);
    }

    [Fact]
    public async Task FriendsWaypoints_ReturnsOnlyAcceptedFriendsWithAWaypointSet()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}"; // accepted, has a waypoint
        var usernameC = $"friend-user-c-{Guid.NewGuid():N}"; // accepted, no waypoint
        var usernameD = $"friend-user-d-{Guid.NewGuid():N}"; // pending only
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var (_, tokenC) = await RegisterAndLoginAsync(usernameC, "correct-horse-battery-staple");
        await RegisterAndLoginAsync(usernameD, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        await SendRequestAsync(tokenA, usernameC);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenC));

        await SendRequestAsync(tokenA, usernameD);

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Spot", Latitude = 10.0, Longitude = 20.0 }));

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/waypoints", tokenA));
        response.EnsureSuccessStatusCode();
        var waypoints = await response.Content.ReadFromJsonAsync<List<FriendWaypointDto>>();

        Assert.Single(waypoints!);
        Assert.Equal(idB, waypoints!.Single().UserId);
    }

    [Fact]
    public async Task FriendsWaypoints_ReturnsOneRowPerNest_WhenAFriendHasMultipleNests()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Home", Latitude = 10.0, Longitude = 20.0, IsPublic = false }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Work", Latitude = 11.0, Longitude = 21.0, IsPublic = true }));

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/waypoints", tokenA));
        response.EnsureSuccessStatusCode();
        var waypoints = await response.Content.ReadFromJsonAsync<List<FriendWaypointDto>>();

        Assert.Equal(2, waypoints!.Count);
        Assert.All(waypoints, w => Assert.Equal(idB, w.UserId));
        Assert.Equal(2, waypoints.Select(w => w.Id).Distinct().Count());
    }

    [Fact]
    public async Task Remove_ClearsFriendshipFromBothSides()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var removeResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/friends/{idB}", tokenA));
        removeResponse.EnsureSuccessStatusCode();

        var friendsOfA = await GetFriendsAsync(tokenA);
        var friendsOfB = await GetFriendsAsync(tokenB);

        Assert.DoesNotContain(friendsOfA, f => f.Id == idB);
        Assert.DoesNotContain(friendsOfB, f => f.Id == idA);
    }

    [Fact]
    public async Task Decline_ClearsPendingRequestFromBothSides()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);

        var declineResponse = await _client.SendAsync(
            AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/decline", tokenB));
        declineResponse.EnsureSuccessStatusCode();

        var incomingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/requests/incoming", tokenB));
        var incoming = await incomingResponse.Content.ReadFromJsonAsync<List<FriendRequestDto>>();
        Assert.DoesNotContain(incoming!, r => r.Id == idA);

        var outgoingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/requests/outgoing", tokenA));
        var outgoing = await outgoingResponse.Content.ReadFromJsonAsync<List<FriendRequestDto>>();
        Assert.DoesNotContain(outgoing!, r => r.Id == idB);
    }

    [Fact]
    public async Task Block_PreventsTheBlockedUserFromSendingARequest()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var blockResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/{idB}/block", tokenA));
        blockResponse.EnsureSuccessStatusCode();

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenB,
            new { Username = usernameA }));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);

        var blockedList = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/blocked", tokenA));
        blockedList.EnsureSuccessStatusCode();
        var blocked = await blockedList.Content.ReadFromJsonAsync<List<FriendRequestDto>>();
        Assert.Contains(blocked!, b => b.Id == idB);
    }

    [Fact]
    public async Task Unblock_AllowsARequestAgain()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/{idB}/block", tokenA));
        await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/friends/{idB}/block", tokenA));

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenB,
            new { Username = usernameA }));

        Assert.True(response.IsSuccessStatusCode);
    }

    [Fact]
    public async Task SetColor_WithInvalidColor_ReturnsBadRequest()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Put, $"/friends/{idB}/color", tokenA,
            new { Color = "#NOTACOLOR" }));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetColor_ForNonFriend_ReturnsNotFound()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (_, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, _) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Put, $"/friends/{idB}/color", tokenA,
            new { Color = "#E53935" }));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task FriendsBirds_ReturnsOnlyAcceptedFriendsInFlightBirds()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}"; // accepted, has a bird in flight
        var usernameC = $"friend-user-c-{Guid.NewGuid():N}"; // accepted, no birds in flight
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (idB, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var (_, tokenC) = await RegisterAndLoginAsync(usernameC, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));
        await SendRequestAsync(tokenA, usernameC);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenC));

        var homeResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Home", Latitude = 10.0, Longitude = 20.0, IsPublic = false }));
        var home = await homeResponse.Content.ReadFromJsonAsync<WaypointDto>();
        var awayResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Away", Latitude = 30.0, Longitude = 40.0, IsPublic = true }));
        var away = await awayResponse.Content.ReadFromJsonAsync<WaypointDto>();

        var composeRequest = new HttpRequestMessage(HttpMethod.Post, "/birds/compose")
        {
            Headers = { Authorization = new AuthenticationHeaderValue("Bearer", tokenB) },
            Content = new MultipartFormDataContent
            {
                { new StringContent("Cro"), "type" },
                { new StringContent("B's Bird"), "name" },
                { new StringContent(home!.Id), "originNestId" },
                { new StringContent(away!.Id), "destinationId" },
                { new StringContent("On my way"), "content" },
            }
        };
        var composeResponse = await _client.SendAsync(composeRequest);
        composeResponse.EnsureSuccessStatusCode();
        var birdToSend = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/birds", tokenA));
        response.EnsureSuccessStatusCode();
        var friendsBirds = await response.Content.ReadFromJsonAsync<List<FriendBirdDto>>();

        var inFlight = Assert.Single(friendsBirds!);
        Assert.Equal(idB, inFlight.UserId);
        Assert.Equal(usernameB, inFlight.Username);
        Assert.Equal(birdToSend.Id, inFlight.Id);
        Assert.NotNull(inFlight.NestFromId);
        Assert.Equal(away.Id, inFlight.NestToId);
    }

    [Fact]
    public async Task FriendsBirds_ExposesContentOnlyForPublicBirds()
    {
        var usernameA = $"friend-user-a-{Guid.NewGuid():N}";
        var usernameB = $"friend-user-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await SendRequestAsync(tokenA, usernameB);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var homeResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Home", Latitude = 10.0, Longitude = 20.0, IsPublic = false }));
        var home = await homeResponse.Content.ReadFromJsonAsync<WaypointDto>();
        var awayResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", tokenB,
            new { Name = "B's Away", Latitude = 30.0, Longitude = 40.0, IsPublic = true }));
        var away = await awayResponse.Content.ReadFromJsonAsync<WaypointDto>();

        async Task<BirdDto> ComposeAsync(string name, bool isPublic)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose")
            {
                Headers = { Authorization = new AuthenticationHeaderValue("Bearer", tokenB) },
                Content = new MultipartFormDataContent
                {
                    { new StringContent("Cro"), "type" },
                    { new StringContent(name), "name" },
                    { new StringContent(home!.Id), "originNestId" },
                    { new StringContent(away!.Id), "destinationId" },
                    { new StringContent("secret payload"), "content" },
                    { new StringContent(isPublic.ToString()), "isPublic" },
                }
            };
            var response = await _client.SendAsync(request);
            response.EnsureSuccessStatusCode();
            return (await response.Content.ReadFromJsonAsync<BirdDto>())!;
        }

        var publicBird = await ComposeAsync("Public Bird", isPublic: true);
        var privateBird = await ComposeAsync("Private Bird", isPublic: false);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/friends/birds", tokenA));
        response.EnsureSuccessStatusCode();
        var friendsBirds = await response.Content.ReadFromJsonAsync<List<FriendBirdDto>>();

        var publicResult = friendsBirds!.Single(b => b.Id == publicBird.Id);
        Assert.True(publicResult.IsPublic);
        Assert.Equal("secret payload", publicResult.Content);

        var privateResult = friendsBirds!.Single(b => b.Id == privateBird.Id);
        Assert.False(privateResult.IsPublic);
        Assert.Null(privateResult.Content);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record FriendDto(string Id, string Username, string? Color);
    private record FriendRequestDto(string Id, string Username);
    private record FriendWaypointDto(string Id, string UserId, string Username, string? Color, double Latitude, double Longitude);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude);
    private record BirdDto(string Id, string? CurrentNestId, bool IsTraveling);
    private record FriendBirdDto(
        string Id, string UserId, string Username, string? Color, string? NestFromId, string? NestToId,
        bool IsPublic, string? Content);
}
