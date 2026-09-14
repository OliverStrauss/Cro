using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class ShooEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public ShooEndpointTests(WebApplicationFactory<Program> factory)
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

    private async Task<WaypointDto> CreateWaypointAsync(string token, string name, double lat, double lng, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

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

    private Task<HttpResponseMessage> ListOwnBirdsAsync(string token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));

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

    private Task<HttpResponseMessage> ShooAsync(string token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/shoo", token));

    // Establishes an accepted friendship, then composes a bird straight from A's nest to B's
    // nest at the same coordinates (instant arrival), resolving the lazy arrival via GET
    // /birds so the delivered bird is actually resident by the time the test shoos it - same
    // helper shape as PinEndpointTests.DeliverBirdAsync.
    private async Task<(string SenderUsername, string BirdId, string SenderToken, string ReceiverToken)> DeliverBirdAsync(
        string birdName, string content, bool isPublic = false)
    {
        var senderUsername = $"shoo-sender-{Guid.NewGuid():N}";
        var receiverUsername = $"shoo-receiver-{Guid.NewGuid():N}";
        var (senderId, senderToken) = await RegisterAndLoginAsync(senderUsername, SeedPassword);
        var (_, receiverToken) = await RegisterAndLoginAsync(receiverUsername, SeedPassword);

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", senderToken, new { Username = receiverUsername }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{senderId}/accept", receiverToken));

        var origin = await CreateWaypointAsync(senderToken, "Sender Nest", 40.0, -90.0);
        var destination = await CreateWaypointAsync(receiverToken, "Receiver Nest", 40.0, -90.0);

        var composeResponse = await ComposeBirdAsync(senderToken, birdName, origin.Id, destination.Id, content, isPublic);
        composeResponse.EnsureSuccessStatusCode();
        var composed = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;

        (await ListOwnBirdsAsync(senderToken)).EnsureSuccessStatusCode();

        return (senderUsername, composed.Id, senderToken, receiverToken);
    }

    [Fact]
    public async Task ShooDeliveredBird_SendsItTravelingBackToSendersHome_AndNotifiesSender()
    {
        var (_, birdId, senderToken, receiverToken) = await DeliverBirdAsync("Wanderer", "on my way");

        var shooResponse = await ShooAsync(receiverToken, birdId);
        shooResponse.EnsureSuccessStatusCode();
        var shooed = (await shooResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        Assert.True(shooed.IsTraveling);

        var notificationsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/notifications", senderToken));
        notificationsResponse.EnsureSuccessStatusCode();
        var notifications = await notificationsResponse.Content.ReadFromJsonAsync<List<EventDto>>();
        Assert.Contains(notifications!, e => e.Kind == "BirdShooed" && e.TargetId == birdId);
    }

    [Fact]
    public async Task ShooBird_EventuallyLandsBackAtSendersHomeNest()
    {
        var (_, birdId, senderToken, receiverToken) = await DeliverBirdAsync("Boomerang", "back soon");

        (await ShooAsync(receiverToken, birdId)).EnsureSuccessStatusCode();

        // Same coordinates as the sender's home nest, so travel time is effectively zero -
        // the very next GET /birds resolves the arrival, same lazy-arrival pattern the rest
        // of BirdService relies on (see ResolveArrivalIfDueAsync).
        var listResponse = await ListOwnBirdsAsync(senderToken);
        listResponse.EnsureSuccessStatusCode();
        var birds = await listResponse.Content.ReadFromJsonAsync<List<BirdDto>>();
        var landed = Assert.Single(birds!, b => b.Id == birdId);
        Assert.False(landed.IsTraveling);
    }

    [Fact]
    public async Task ShooOwnBird_ReturnsBadRequest()
    {
        // A user has only one own nest, so a bird can't be composed "to" itself - it has to
        // travel away (to a friend's nest here) and then be called back home before it's ever
        // sitting at its own owner's nest again. Same setup PinEndpointTests.PinOwnBird_
        // ReturnsBadRequest uses.
        var username = $"shoo-self-{Guid.NewGuid():N}";
        var friendUsername = $"shoo-self-friend-{Guid.NewGuid():N}";
        var (userId, token) = await RegisterAndLoginAsync(username, SeedPassword);
        var (_, friendToken) = await RegisterAndLoginAsync(friendUsername, SeedPassword);
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", token, new { Username = friendUsername }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{userId}/accept", friendToken));

        var ownNest = await CreateWaypointAsync(token, "My Nest", 41.0, -95.0);
        var friendNest = await CreateWaypointAsync(friendToken, "Friend Nest", 41.0, -95.0);

        var composeResponse = await ComposeBirdAsync(token, "Self Bird", ownNest.Id, friendNest.Id, "away for a bit");
        composeResponse.EnsureSuccessStatusCode();
        var bird = (await composeResponse.Content.ReadFromJsonAsync<BirdDto>())!;
        (await ListOwnBirdsAsync(token)).EnsureSuccessStatusCode();

        (await SendBirdAsync(token, bird.Id, ownNest.Id, "back home")).EnsureSuccessStatusCode();
        (await ListOwnBirdsAsync(token)).EnsureSuccessStatusCode();

        var response = await ShooAsync(token, bird.Id);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ShooBird_NotCurrentlyDeliveredToCaller_ReturnsNotFound()
    {
        var (_, birdId, _, _) = await DeliverBirdAsync("Someone Else's", "not yours");

        var (_, strangerToken) = await RegisterAndLoginAsync($"shoo-stranger-{Guid.NewGuid():N}", SeedPassword);
        var response = await ShooAsync(strangerToken, birdId);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ShooBird_Twice_SecondCallReturnsNotFound()
    {
        var (_, birdId, _, receiverToken) = await DeliverBirdAsync("One Shot", "leaving now");

        (await ShooAsync(receiverToken, birdId)).EnsureSuccessStatusCode();
        var secondResponse = await ShooAsync(receiverToken, birdId);

        Assert.Equal(HttpStatusCode.NotFound, secondResponse.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UserResponseDto(string Id, string Username, string Email);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record BirdDto(string Id, string UserId, string Name, bool IsTraveling, bool IsPublic);
    private record EventDto(string Id, string Kind, string DisplayText, string? TargetType, string? TargetId, bool IsNotification, bool IsRead, DateTimeOffset CreatedAt, string? SourceUserId);
}
