using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;

    public BirdEndpointTests(WebApplicationFactory<Program> factory)
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

    private Task<HttpResponseMessage> ListBirdsAsync(string? token) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Get, "/birds", token));

    private Task<HttpResponseMessage> CreateWaypointAsync(string? token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token, new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));

    [Fact]
    public async Task ListBirds_ForNewUser_LazilyCreatesThreeBirds()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await ListBirdsAsync(token);
        response.EnsureSuccessStatusCode();
        var birds = await response.Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Equal(3, birds!.Count);
        Assert.Equal(["Bird 1", "Bird 2", "Bird 3"], birds.Select(b => b.Name).OrderBy(n => n));
        Assert.All(birds, b =>
        {
            Assert.Null(b.CurrentNestId);
            Assert.False(b.IsTraveling);
        });
    }

    [Fact]
    public async Task ListBirds_CalledTwice_DoesNotCreateDuplicates()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        await ListBirdsAsync(token);
        var secondResponse = await ListBirdsAsync(token);
        var birds = await secondResponse.Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Equal(3, birds!.Count);
    }

    [Fact]
    public async Task CreatingANest_AssignsUnassignedBirdsToIt()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        await ListBirdsAsync(token);

        var created = await (await CreateWaypointAsync(token, "Backyard")).Content.ReadFromJsonAsync<WaypointDto>();

        var response = await ListBirdsAsync(token);
        var birds = await response.Content.ReadFromJsonAsync<List<BirdDto>>();
        Assert.Equal(3, birds!.Count);
        Assert.All(birds, b => Assert.Equal(created!.Id, b.CurrentNestId));
    }

    [Fact]
    public async Task CreatingASecondNest_DoesNotReassignAlreadyAssignedBirds()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        await ListBirdsAsync(token);
        var first = await (await CreateWaypointAsync(token, "Backyard")).Content.ReadFromJsonAsync<WaypointDto>();

        await CreateWaypointAsync(token, "Front Porch", 42.1, -93.6, isPublic: true);

        var response = await ListBirdsAsync(token);
        var birds = await response.Content.ReadFromJsonAsync<List<BirdDto>>();
        Assert.All(birds!, b => Assert.Equal(first!.Id, b.CurrentNestId));
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

        var birdsA = await (await ListBirdsAsync(tokenA)).Content.ReadFromJsonAsync<List<BirdDto>>();
        var birdsB = await (await ListBirdsAsync(tokenB)).Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Equal(3, birdsA!.Count);
        Assert.Equal(3, birdsB!.Count);
        Assert.All(birdsA, b => Assert.All(birdsB, other => Assert.NotEqual(b.Id, other.Id)));
        Assert.Single(birdsA.Select(b => b.UserId).Distinct());
        Assert.NotEqual(birdsA[0].UserId, birdsB[0].UserId);
    }

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
