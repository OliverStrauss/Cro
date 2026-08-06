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
            new QueryDefinition("SELECT VALUE COUNT(1) FROM c WHERE c.id = @userId")
                .WithParameter("@userId", userId));
        var page = await query.ReadNextAsync();
        return (int)page.First();
    }

    [Fact]
    public async Task SetThenGetWaypoint_RoundTripsSuccessfully()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var setResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", token,
            new { Name = "Backyard", Latitude = 42.0, Longitude = -93.5 }));
        setResponse.EnsureSuccessStatusCode();

        var getResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoint", token));
        getResponse.EnsureSuccessStatusCode();

        var waypoint = await getResponse.Content.ReadFromJsonAsync<WaypointDto>();
        Assert.NotNull(waypoint);
        Assert.Equal("Backyard", waypoint!.Name);
        Assert.Equal(42.0, waypoint.Latitude);
        Assert.Equal(-93.5, waypoint.Longitude);
    }

    [Fact]
    public async Task GetWaypoint_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoint", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task PutWaypoint_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", token: null,
            new { Name = "Backyard", Latitude = 42.0, Longitude = -93.5 }));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetWaypoint_ForUserWhoNeverSetOne_ReturnsNotFound()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoint", token));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SettingNewWaypoint_ReplacesOldOne_NotASecondDocument()
    {
        var username = $"waypoint-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", token,
            new { Name = "Backyard", Latitude = 42.0, Longitude = -93.5 }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", token,
            new { Name = "Front Porch", Latitude = 42.1, Longitude = -93.6 }));

        var getResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoint", token));
        var waypoint = await getResponse.Content.ReadFromJsonAsync<WaypointDto>();
        Assert.Equal("Front Porch", waypoint!.Name);

        var documentCount = await CountWaypointDocumentsAsync(waypoint.Id);
        Assert.Equal(1, documentCount);
    }

    [Fact]
    public async Task Waypoint_IsScopedToTheAuthenticatedUser()
    {
        var usernameA = $"waypoint-user-a-{Guid.NewGuid():N}";
        var usernameB = $"waypoint-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        var tokenB = await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", tokenA,
            new { Name = "User A's Spot", Latitude = 1.0, Longitude = 1.0 }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Put, "/waypoint", tokenB,
            new { Name = "User B's Spot", Latitude = 2.0, Longitude = 2.0 }));

        var getResponseA = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/waypoint", tokenA));
        var waypointA = await getResponseA.Content.ReadFromJsonAsync<WaypointDto>();

        Assert.Equal("User A's Spot", waypointA!.Name);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt);
}
