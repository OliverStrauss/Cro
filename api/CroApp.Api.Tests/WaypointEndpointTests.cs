using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class WaypointEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;
    private readonly string _connectionString;

    public WaypointEndpointTests(WebApplicationFactory<Program> factory)
    {
        _connectionString = Environment.GetEnvironmentVariable("CosmosDb__ConnectionString")
            ?? DefaultEmulatorConnectionString;

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["CosmosDb:UseEmulator"] = "true",
                    ["CosmosDb:ConnectionString"] = _connectionString,
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

    private Task<HttpResponseMessage> CreateWaypointAsync(string? token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token, new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));

    private async Task<int> CountWaypointDocumentsAsync(string userId)
    {
        var clientOptions = new CosmosClientOptions
        {
            HttpClientFactory = () => new HttpClient(new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
            }),
            ConnectionMode = ConnectionMode.Gateway
        };
        using var cosmosClient = new CosmosClient(_connectionString, clientOptions);
        var container = cosmosClient.GetContainer("CroApp", "Waypoints");

        var query = container.GetItemQueryIterator<dynamic>(
            new QueryDefinition("SELECT VALUE COUNT(1) FROM c WHERE c.userId = @userId")
                .WithParameter("@userId", userId));
        var page = await query.ReadNextAsync();
        return (int)page.First();
    }

    [Fact]
    public async Task CreateThenListWaypoint_RoundTripsSuccessfully()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var createResponse = await CreateWaypointAsync(token, "Backyard");
        createResponse.EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        listResponse.EnsureSuccessStatusCode();
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();

        var waypoint = Assert.Single(waypoints!);
        Assert.Equal("Backyard", waypoint.Name);
        Assert.Equal(42.0, waypoint.Latitude);
        Assert.Equal(-93.5, waypoint.Longitude);
    }

    [Fact]
    public async Task ListWaypoints_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task CreateWaypoint_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token: null,
            new { Name = "Backyard", Latitude = 42.0, Longitude = -93.5 }));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task UpdateWaypoint_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoints/some-id", token: null,
            new { Name = "Backyard", Latitude = 42.0, Longitude = -93.5 }));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task DeleteWaypoint_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, "/waypoints/some-id", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ListWaypoints_ForUserWhoNeverCreatedOne_ReturnsEmptyList()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        response.EnsureSuccessStatusCode();
        var waypoints = await response.Content.ReadFromJsonAsync<List<WaypointDto>>();

        Assert.Empty(waypoints!);
    }

    [Fact]
    public async Task CreatingMultipleWaypoints_CreatesSeparateDocuments()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var first = await (await CreateWaypointAsync(token, "Backyard")).Content.ReadFromJsonAsync<WaypointDto>();
        await CreateWaypointAsync(token, "Front Porch", 42.1, -93.6, isPublic: true);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();
        Assert.Equal(2, waypoints!.Count);

        var documentCount = await CountWaypointDocumentsAsync(first!.UserId);
        Assert.Equal(2, documentCount);
    }

    [Fact]
    public async Task CreatingOnePrivateAndOnePublicNest_Succeeds()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var privateResponse = await CreateWaypointAsync(token, "Backyard", isPublic: false);
        Assert.Equal(HttpStatusCode.Created, privateResponse.StatusCode);

        var publicResponse = await CreateWaypointAsync(token, "The Library", isPublic: true);
        Assert.Equal(HttpStatusCode.Created, publicResponse.StatusCode);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();
        Assert.Equal(2, waypoints!.Count);
        Assert.Contains(waypoints, w => !w.IsPublic);
        Assert.Contains(waypoints, w => w.IsPublic);
    }

    [Fact]
    public async Task CreatingASecondPrivateNest_ReturnsConflict()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var first = await CreateWaypointAsync(token, "Backyard", isPublic: false);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await CreateWaypointAsync(token, "Front Porch", isPublic: false);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task CreatingASecondPublicNest_ReturnsConflict()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var first = await CreateWaypointAsync(token, "The Library", isPublic: true);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await CreateWaypointAsync(token, "The Gym", isPublic: true);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task UpdateWaypoint_ChangesNameAndLocation()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var created = await (await CreateWaypointAsync(token, "Backyard")).Content.ReadFromJsonAsync<WaypointDto>();

        var updateResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Put, $"/waypoints/{created!.Id}", token,
            new { Name = "Front Porch", Latitude = 1.0, Longitude = 2.0 }));
        updateResponse.EnsureSuccessStatusCode();

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        var waypoint = Assert.Single((await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>())!);
        Assert.Equal(created.Id, waypoint.Id);
        Assert.Equal("Front Porch", waypoint.Name);
        Assert.Equal(1.0, waypoint.Latitude);
        Assert.Equal(2.0, waypoint.Longitude);
    }

    [Fact]
    public async Task UpdateWaypoint_ForAnotherUsersNest_ReturnsNotFound()
    {
        var usernameA = $"waypoint-user-a-{Guid.NewGuid():N}";
        var usernameB = $"waypoint-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var tokenB = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var created = await (await CreateWaypointAsync(tokenA, "User A's Spot")).Content.ReadFromJsonAsync<WaypointDto>();

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Put, $"/waypoints/{created!.Id}", tokenB,
            new { Name = "Hijacked", Latitude = 9.0, Longitude = 9.0 }));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteWaypoint_RemovesIt()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var created = await (await CreateWaypointAsync(token, "Backyard")).Content.ReadFromJsonAsync<WaypointDto>();

        var deleteResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/waypoints/{created!.Id}", token));
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", token));
        var waypoints = await listResponse.Content.ReadFromJsonAsync<List<WaypointDto>>();
        Assert.Empty(waypoints!);
    }

    [Fact]
    public async Task DeleteWaypoint_ForAnotherUsersNest_ReturnsNotFound()
    {
        var usernameA = $"waypoint-user-a-{Guid.NewGuid():N}";
        var usernameB = $"waypoint-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var tokenB = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");
        var created = await (await CreateWaypointAsync(tokenA, "User A's Spot")).Content.ReadFromJsonAsync<WaypointDto>();

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/waypoints/{created!.Id}", tokenB));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Waypoints_AreScopedToTheAuthenticatedUser()
    {
        var usernameA = $"waypoint-user-a-{Guid.NewGuid():N}";
        var usernameB = $"waypoint-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var tokenB = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await CreateWaypointAsync(tokenA, "User A's Spot", 1.0, 1.0);
        await CreateWaypointAsync(tokenB, "User B's Spot", 2.0, 2.0);

        var listResponseA = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoints", tokenA));
        var waypointsA = await listResponseA.Content.ReadFromJsonAsync<List<WaypointDto>>();

        var waypointA = Assert.Single(waypointsA!);
        Assert.Equal("User A's Spot", waypointA.Name);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
}
