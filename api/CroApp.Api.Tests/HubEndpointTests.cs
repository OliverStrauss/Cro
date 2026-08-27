using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class HubEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public HubEndpointTests(WebApplicationFactory<Program> factory)
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

        return await LoginAsync(username, password);
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

    private Task<HttpResponseMessage> CreateHubAsync(string? token, string name, double lat = 42.0, double lng = -93.6) =>
        _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token, new { Name = name, Latitude = lat, Longitude = lng, Category = "Library" }));

    [Fact]
    public async Task Admin1_CanCreateAHub()
    {
        var token = await LoginAsync("Admin 1", SeedPassword);

        var response = await CreateHubAsync(token, $"Test Library {Guid.NewGuid():N}");
        response.EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var hub = await response.Content.ReadFromJsonAsync<HubDto>();
        Assert.Equal("Approved", hub!.Status);
        Assert.Equal(42.0, hub.Latitude);
        Assert.Equal(-93.6, hub.Longitude);
    }

    [Fact]
    public async Task NonAdmin_CreatingAHub_ReturnsForbidden()
    {
        var username = $"hub-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await CreateHubAsync(token, "Should Not Exist");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task CreateHub_WithoutToken_ReturnsUnauthorized()
    {
        var response = await CreateHubAsync(token: null, "Should Not Exist");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ListHubs_ReturnsHubsCreatedByAdmin_ToAnyAuthenticatedUser()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hubName = $"Test Gym {Guid.NewGuid():N}";
        var created = await (await CreateHubAsync(adminToken, hubName)).Content.ReadFromJsonAsync<HubDto>();

        var username = $"hub-viewer-{Guid.NewGuid():N}";
        var viewerToken = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", viewerToken));
        listResponse.EnsureSuccessStatusCode();
        var hubs = await listResponse.Content.ReadFromJsonAsync<List<HubDto>>();

        Assert.Contains(hubs!, h => h.Id == created!.Id && h.Name == hubName);
    }

    [Fact]
    public async Task ListHubs_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetHubResidentBirds_ForNonexistentHub_ReturnsNotFound()
    {
        var username = $"hub-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs/does-not-exist/birds", token));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetHubResidentBirds_ForHubWithNoResidents_ReturnsEmptyList_ReachableByAnyUser()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var created = await (await CreateHubAsync(adminToken, $"Empty Hub {Guid.NewGuid():N}")).Content.ReadFromJsonAsync<HubDto>();

        // A different, non-admin, non-creator user can still read who's at a Hub - nobody
        // owns it, unlike a nest's owner-scoped residents endpoint.
        var username = $"hub-viewer-{Guid.NewGuid():N}";
        var viewerToken = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/hubs/{created!.Id}/birds", viewerToken));
        response.EnsureSuccessStatusCode();
        var birds = await response.Content.ReadFromJsonAsync<List<object>>();

        Assert.Empty(birds!);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
}
