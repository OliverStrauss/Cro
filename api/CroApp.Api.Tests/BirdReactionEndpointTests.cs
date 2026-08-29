using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdReactionEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;

    public BirdReactionEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["Jwt:SigningKey"] = UsersEndpointTests.TestJwtSigningKey,
                    ["Jwt:Issuer"] = "CroApp.Api.Tests",
                    ["Jwt:Audience"] = "CroApp.Api.Tests"
                });
            });
        });

        _client = configuredFactory.CreateClient();
    }

    private async Task<string> RegisterAndLoginAsync(string username, string password)
    {
        var createResponse = await _client.PostAsJsonAsync("/users",
            new { Username = username, Email = $"{username}@example.com", Password = password });
        createResponse.EnsureSuccessStatusCode();

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

    private async Task<BirdDto> ComposeBirdAsync(string token, string originId, string destinationId, bool isPublic)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose")
        {
            Headers = { Authorization = new AuthenticationHeaderValue("Bearer", token) },
            Content = new MultipartFormDataContent
            {
                { new StringContent("Cro"), "type" },
                { new StringContent("Test Bird"), "name" },
                { new StringContent(originId), "originNestId" },
                { new StringContent(destinationId), "destinationId" },
                { new StringContent("hello"), "content" },
                { new StringContent(isPublic.ToString()), "isPublic" },
            }
        };
        var response = await _client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<BirdDto>())!;
    }

    private Task<HttpResponseMessage> AddReactionAsync(string? token, string birdId, string emoji) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Put, $"/birds/{birdId}/reactions/{Uri.EscapeDataString(emoji)}", token));

    private Task<HttpResponseMessage> RemoveReactionAsync(string? token, string birdId, string emoji) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/birds/{birdId}/reactions/{Uri.EscapeDataString(emoji)}", token));

    private Task<HttpResponseMessage> GetReactionsAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/birds/{birdId}/reactions", token));

    [Fact]
    public async Task ReactingToAPublicBird_Succeeds()
    {
        var token = await RegisterAndLoginAsync($"react-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(token, origin.Id, dest.Id, isPublic: true);

        var response = await AddReactionAsync(token, bird.Id, "👍");
        response.EnsureSuccessStatusCode();
        var summary = await response.Content.ReadFromJsonAsync<List<ReactionSummaryDto>>();

        var entry = Assert.Single(summary!);
        Assert.Equal("👍", entry.Emoji);
        Assert.Equal(1, entry.Count);
        Assert.True(entry.ReactedByMe);
    }

    [Fact]
    public async Task ReactingToAPrivateBird_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"react-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(token, origin.Id, dest.Id, isPublic: false);

        var response = await AddReactionAsync(token, bird.Id, "👍");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ReactingWithAnUnsupportedEmoji_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"react-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(token, origin.Id, dest.Id, isPublic: true);

        var response = await AddReactionAsync(token, bird.Id, "🦖");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task DuplicateSameEmojiFromSameUser_StaysOneRow()
    {
        var senderToken = await RegisterAndLoginAsync($"react-sender-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(senderToken, "Home", isPublic: false);
        var dest = await CreateNestAsync(senderToken, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(senderToken, origin.Id, dest.Id, isPublic: true);

        var reactorToken = await RegisterAndLoginAsync($"react-reactor-{Guid.NewGuid():N}", "correct-horse-battery-staple");

        (await AddReactionAsync(reactorToken, bird.Id, "❤️")).EnsureSuccessStatusCode();
        var second = await AddReactionAsync(reactorToken, bird.Id, "❤️");
        second.EnsureSuccessStatusCode();
        var summary = await second.Content.ReadFromJsonAsync<List<ReactionSummaryDto>>();

        var entry = Assert.Single(summary!);
        Assert.Equal(1, entry.Count);
    }

    [Fact]
    public async Task DifferentEmojisFromSameUser_BothPersist()
    {
        var token = await RegisterAndLoginAsync($"react-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(token, origin.Id, dest.Id, isPublic: true);

        (await AddReactionAsync(token, bird.Id, "👍")).EnsureSuccessStatusCode();
        var response = await AddReactionAsync(token, bird.Id, "😮");
        response.EnsureSuccessStatusCode();
        var summary = await response.Content.ReadFromJsonAsync<List<ReactionSummaryDto>>();

        Assert.Equal(2, summary!.Count);
        Assert.Contains(summary, e => e.Emoji == "👍");
        Assert.Contains(summary, e => e.Emoji == "😮");
    }

    [Fact]
    public async Task RemovingAReaction_RemovesExactlyOne()
    {
        var token = await RegisterAndLoginAsync($"react-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);
        var bird = await ComposeBirdAsync(token, origin.Id, dest.Id, isPublic: true);

        (await AddReactionAsync(token, bird.Id, "👍")).EnsureSuccessStatusCode();
        (await AddReactionAsync(token, bird.Id, "😮")).EnsureSuccessStatusCode();

        var deleteResponse = await RemoveReactionAsync(token, bird.Id, "👍");
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var afterResponse = await GetReactionsAsync(token, bird.Id);
        var after = await afterResponse.Content.ReadFromJsonAsync<List<ReactionSummaryDto>>();
        var remaining = Assert.Single(after!);
        Assert.Equal("😮", remaining.Emoji);
    }

    [Fact]
    public async Task GetReactions_WithoutToken_ReturnsUnauthorized()
    {
        var response = await GetReactionsAsync(null, "some-id");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record BirdDto(string Id, bool IsPublic);
    private record ReactionSummaryDto(string Emoji, int Count, bool ReactedByMe);
}
