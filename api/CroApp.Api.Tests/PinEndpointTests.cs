using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class PinEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public PinEndpointTests(WebApplicationFactory<Program> factory)
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

    // Establishes an accepted friendship, then composes a bird straight from A's nest to B's
    // nest at the same coordinates (instant arrival), resolving the lazy arrival via GET
    // /birds so the delivered bird is actually resident by the time the test pins it.
    private async Task<(string SenderUsername, string BirdId, string SenderToken, string ReceiverToken)> DeliverBirdAsync(
        string birdName, string content, bool isPublic)
    {
        var senderUsername = $"pin-sender-{Guid.NewGuid():N}";
        var receiverUsername = $"pin-receiver-{Guid.NewGuid():N}";
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

    private Task<HttpResponseMessage> PinAsync(string token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/pin", token));

    [Fact]
    public async Task PinPrivateBird_VisibleOnlyToReceiver_AndNotifiesSender()
    {
        var (senderUsername, birdId, senderToken, receiverToken) = await DeliverBirdAsync("Private Note", "just for you", isPublic: false);

        var pinResponse = await PinAsync(receiverToken, birdId);
        pinResponse.EnsureSuccessStatusCode();
        var pin = (await pinResponse.Content.ReadFromJsonAsync<PinnedBirdDto>())!;
        Assert.False(pin.IsPublic);
        Assert.Equal(senderUsername, pin.SenderUsername);
        Assert.Equal("just for you", pin.Content);

        var mineResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/mine", receiverToken));
        mineResponse.EnsureSuccessStatusCode();
        var mine = await mineResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.Single(mine!, p => p.Id == pin.Id);

        var publicResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/public", senderToken));
        publicResponse.EnsureSuccessStatusCode();
        var publicPins = await publicResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.DoesNotContain(publicPins!, p => p.Id == pin.Id);

        var notificationsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/notifications", senderToken));
        notificationsResponse.EnsureSuccessStatusCode();
        var notifications = await notificationsResponse.Content.ReadFromJsonAsync<List<EventDto>>();
        Assert.Contains(notifications!, e => e.Kind == "BirdPinned" && e.TargetId == pin.Id);
    }

    [Fact]
    public async Task PinPublicBird_AppearsInPublicFeed()
    {
        var (_, birdId, _, receiverToken) = await DeliverBirdAsync("Open Note", "for everyone", isPublic: true);

        var pinResponse = await PinAsync(receiverToken, birdId);
        pinResponse.EnsureSuccessStatusCode();
        var pin = (await pinResponse.Content.ReadFromJsonAsync<PinnedBirdDto>())!;
        Assert.True(pin.IsPublic);

        var (_, strangerToken) = await RegisterAndLoginAsync($"pin-stranger-{Guid.NewGuid():N}", SeedPassword);
        var publicResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/public", strangerToken));
        publicResponse.EnsureSuccessStatusCode();
        var publicPins = await publicResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.Contains(publicPins!, p => p.Id == pin.Id);
    }

    [Fact]
    public async Task PinningTheSameDelivery_Twice_IsIdempotent()
    {
        var (_, birdId, _, receiverToken) = await DeliverBirdAsync("Repeat Note", "hi again", isPublic: false);

        (await PinAsync(receiverToken, birdId)).EnsureSuccessStatusCode();
        var secondResponse = await PinAsync(receiverToken, birdId);
        secondResponse.EnsureSuccessStatusCode();

        var mineResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/mine", receiverToken));
        mineResponse.EnsureSuccessStatusCode();
        var mine = await mineResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.Single(mine!, p => p.BirdId == birdId);
    }

    [Fact]
    public async Task PinBird_NotCurrentlyDeliveredToCaller_ReturnsNotFound()
    {
        var (_, birdId, _, _) = await DeliverBirdAsync("Someone Else's", "not yours", isPublic: false);

        var (_, strangerToken) = await RegisterAndLoginAsync($"pin-stranger-{Guid.NewGuid():N}", SeedPassword);
        var response = await PinAsync(strangerToken, birdId);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task PinOwnBird_ReturnsBadRequest()
    {
        // A user has only one own nest, so a bird can't be composed "to" itself - it has to
        // travel away (to a friend's nest here) and then be called back home before it's ever
        // sitting at its own owner's nest again.
        var username = $"pin-self-{Guid.NewGuid():N}";
        var friendUsername = $"pin-self-friend-{Guid.NewGuid():N}";
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

        var response = await PinAsync(token, bird.Id);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Unpin_ByReceiver_RemovesTheirOwnPin()
    {
        var (_, birdId, _, receiverToken) = await DeliverBirdAsync("Removable Note", "bye", isPublic: false);
        var pin = (await (await PinAsync(receiverToken, birdId)).Content.ReadFromJsonAsync<PinnedBirdDto>())!;

        var deleteResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/pins/{pin.Id}", receiverToken));
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var mineResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/mine", receiverToken));
        mineResponse.EnsureSuccessStatusCode();
        var mine = await mineResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.DoesNotContain(mine!, p => p.Id == pin.Id);
    }

    [Fact]
    public async Task Unpin_PublicPinBySender_TakesItDown()
    {
        var (_, birdId, senderToken, receiverToken) = await DeliverBirdAsync("Takedown Note", "public for now", isPublic: true);
        var pin = (await (await PinAsync(receiverToken, birdId)).Content.ReadFromJsonAsync<PinnedBirdDto>())!;

        var deleteResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/pins/{pin.Id}", senderToken));
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var publicResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/public", senderToken));
        publicResponse.EnsureSuccessStatusCode();
        var publicPins = await publicResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.DoesNotContain(publicPins!, p => p.Id == pin.Id);
    }

    [Fact]
    public async Task Unpin_PrivatePinBySender_IsForbidden()
    {
        var (_, birdId, senderToken, receiverToken) = await DeliverBirdAsync("Private Takedown Attempt", "shh", isPublic: false);
        var pin = (await (await PinAsync(receiverToken, birdId)).Content.ReadFromJsonAsync<PinnedBirdDto>())!;

        var deleteResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/pins/{pin.Id}", senderToken));
        Assert.Equal(HttpStatusCode.NotFound, deleteResponse.StatusCode);

        var mineResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/pins/mine", receiverToken));
        mineResponse.EnsureSuccessStatusCode();
        var mine = await mineResponse.Content.ReadFromJsonAsync<List<PinnedBirdDto>>();
        Assert.Contains(mine!, p => p.Id == pin.Id);
    }

    [Fact]
    public async Task GetPinForBird_ReflectsRealState_AndClearsAfterUnpin()
    {
        var (_, birdId, _, receiverToken) = await DeliverBirdAsync("Status Note", "check me", isPublic: false);

        var beforeResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/birds/{birdId}/pin", receiverToken));
        Assert.Equal(HttpStatusCode.NotFound, beforeResponse.StatusCode);

        var pin = (await (await PinAsync(receiverToken, birdId)).Content.ReadFromJsonAsync<PinnedBirdDto>())!;

        var afterResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/birds/{birdId}/pin", receiverToken));
        afterResponse.EnsureSuccessStatusCode();
        var status = (await afterResponse.Content.ReadFromJsonAsync<PinnedBirdDto>())!;
        Assert.Equal(pin.Id, status.Id);

        (await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/pins/{pin.Id}", receiverToken))).EnsureSuccessStatusCode();

        var afterUnpinResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/birds/{birdId}/pin", receiverToken));
        Assert.Equal(HttpStatusCode.NotFound, afterUnpinResponse.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UserResponseDto(string Id, string Username, string Email);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record BirdDto(string Id, string UserId, string Name, bool IsTraveling, bool IsPublic);
    private record PinnedBirdDto(
        string Id,
        string ReceiverId,
        string SenderId,
        string SenderUsername,
        string BirdId,
        string BirdName,
        string? OriginNestName,
        string Type,
        string? Content,
        string? AudioUrl,
        string? ImageUrl,
        bool IsPublic,
        DateTimeOffset CreatedAt);
    private record EventDto(string Id, string Kind, string DisplayText, string? TargetType, string? TargetId, bool IsNotification, bool IsRead, DateTimeOffset CreatedAt, string? SourceUserId);
}
