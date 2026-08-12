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
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

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
                    ["CosmosDb:BirdsContainerName"] = "Birds",
                    // Deliberately left at the real default (1.0, from appsettings.json - not
                    // overridden here) so a just-sent bird reliably stays "traveling" for the
                    // lifetime of these tests (hours/days of simulated flight time). Arrival
                    // resolution itself is covered separately in BirdArrivalEndpointTests.cs,
                    // which cranks the multiplier up instead.
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

    private async Task<WaypointDto> CreateNestAsync(string token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private async Task<List<BirdDto>> ListBirdsAsync(string token)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<List<BirdDto>>())!;
    }

    private Task<HttpResponseMessage> SendBirdAsync(string? token, string birdId, string nestId, string? content = null) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/send", token, new { NestId = nestId, Content = content }));

    private Task<HttpResponseMessage> GetNestResidentsAsync(string? token, string nestId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/waypoints/{nestId}/birds", token));

    private Task<HttpResponseMessage> MarkReadAsync(string? token, string birdId) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/birds/{birdId}/read", token));

    [Fact]
    public async Task Send_ToOwnOtherNest_MarksItTravelingWithEta()
    {
        var (_, token) = await RegisterAndLoginAsync($"bird-send-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        await ListBirdsAsync(token); // provisions 3 unassigned birds
        var nest1 = await CreateNestAsync(token, "Nest 1", 42.0, -93.5); // auto-assigns them here
        var nest2 = await CreateNestAsync(token, "Nest 2", 42.1, -93.6, isPublic: true);
        var bird = (await ListBirdsAsync(token))[0];

        var response = await SendBirdAsync(token, bird.Id, nest2.Id, "Hello there");
        response.EnsureSuccessStatusCode();
        var sent = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.True(sent!.IsTraveling);
        Assert.Equal(nest2.Id, sent.NestToId);
        Assert.Equal(nest1.Id, sent.NestFromId);
        Assert.Null(sent.CurrentNestId);
        Assert.NotNull(sent.EstimatedArrivalAt);
        Assert.NotNull(sent.DepartedAt);
        Assert.True(sent.EstimatedArrivalAt >= sent.DepartedAt);
        Assert.Equal("Hello there", sent.Content);
    }

    [Fact]
    public async Task Send_AlreadyTravelingBird_ReturnsConflict()
    {
        var (_, token) = await RegisterAndLoginAsync($"bird-send-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        await ListBirdsAsync(token);
        var nest1 = await CreateNestAsync(token, "Nest 1", 42.0, -93.5);
        var nest2 = await CreateNestAsync(token, "Nest 2", 60.0, -93.6, isPublic: true);
        var bird = (await ListBirdsAsync(token))[0];

        var first = await SendBirdAsync(token, bird.Id, nest2.Id);
        first.EnsureSuccessStatusCode();

        var second = await SendBirdAsync(token, bird.Id, nest1.Id);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task Send_ToBirdsCurrentNest_ReturnsBadRequest()
    {
        var (_, token) = await RegisterAndLoginAsync($"bird-send-user-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        await ListBirdsAsync(token);
        var nest1 = await CreateNestAsync(token, "Nest 1");
        var bird = (await ListBirdsAsync(token))[0];

        var response = await SendBirdAsync(token, bird.Id, nest1.Id);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Send_ToNestThatIsNeitherOwnNorFriends_ReturnsNotFound()
    {
        var (_, tokenA) = await RegisterAndLoginAsync($"bird-send-a-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        var (_, tokenC) = await RegisterAndLoginAsync($"bird-send-c-{Guid.NewGuid():N}", "correct-horse-battery-staple");
        await ListBirdsAsync(tokenA);
        await CreateNestAsync(tokenA, "A's Nest");
        var strangersNest = await CreateNestAsync(tokenC, "Stranger's Nest", 10.0, 10.0);
        var bird = (await ListBirdsAsync(tokenA))[0];

        var response = await SendBirdAsync(tokenA, bird.Id, strangersNest.Id);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Send_ToFriendsNest_Succeeds()
    {
        var usernameA = $"bird-friend-a-{Guid.NewGuid():N}";
        var usernameB = $"bird-friend-b-{Guid.NewGuid():N}";
        var (idA, tokenA) = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var (_, tokenB) = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = usernameB }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        await ListBirdsAsync(tokenA);
        await CreateNestAsync(tokenA, "A's Nest");
        var bNest = await CreateNestAsync(tokenB, "B's Nest", 50.0, 50.0);
        var bird = (await ListBirdsAsync(tokenA))[0];

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
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt);
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
        DateTimeOffset UpdatedAt);
}
