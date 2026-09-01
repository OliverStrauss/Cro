using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using CroApp.Api.Repositories;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace CroApp.Api.Tests;

public class HubEndpointTests : IClassFixture<WebApplicationFactory<Program>>, IAsyncLifetime
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;

    // Every Hub this test class creates or suggests, keyed by id -> its current status, so
    // DisposeAsync can delete them from the shared local emulator's Hubs container instead of
    // leaving permanent "Test Library ..."/"Empty Hub ..." rows behind on every test run.
    private readonly Dictionary<string, string> _hubIdToStatus = new();

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

        _factory = configuredFactory;
        _client = configuredFactory.CreateClient();
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var hubRepository = scope.ServiceProvider.GetRequiredService<IHubRepository>();
        foreach (var (id, status) in _hubIdToStatus)
        {
            try
            {
                await hubRepository.DeleteAsync(id, status);
            }
            catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
            {
                // Already deleted by the test itself (e.g. a rejected suggestion).
            }
        }
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

    private async Task<HttpResponseMessage> CreateHubAsync(string? token, string name, double lat = 42.0, double lng = -93.6)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token, new { Name = name, Latitude = lat, Longitude = lng, Category = "Landmark" }));
        await TrackHubFromResponseAsync(response);
        return response;
    }

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

    [Fact]
    public async Task CreateHub_WithInvalidCategory_ReturnsBadRequest()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", adminToken,
            new { Name = "Should Not Exist", Latitude = 42.0, Longitude = -93.6, Category = "Not A Real Category" }));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SuggestHub_WithInvalidCategory_ReturnsBadRequest()
    {
        var username = $"hub-suggester-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hub-suggestions", token,
            new { Name = "Should Not Exist", Latitude = 42.3, Longitude = -93.4, Category = "Not A Real Category" }));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private async Task<HttpResponseMessage> SuggestHubAsync(string token, string name, double lat = 42.3, double lng = -93.4)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hub-suggestions", token, new { Name = name, Latitude = lat, Longitude = lng, Category = "Park" }));
        await TrackHubFromResponseAsync(response);
        return response;
    }

    // WebApplicationFactory's in-memory TestServer response stream isn't rewindable, so
    // ReadFromJsonAsync can only be called once per response - read the body ourselves here,
    // pull out just the id/status we need for cleanup, then hand the caller back a fresh,
    // re-readable HttpContent so their own ReadFromJsonAsync<HubDto> still works.
    private async Task TrackHubFromResponseAsync(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
        {
            return;
        }
        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        _hubIdToStatus[doc.RootElement.GetProperty("id").GetString()!] = doc.RootElement.GetProperty("status").GetString()!;
        response.Content = new StringContent(json, Encoding.UTF8, "application/json");
    }

    [Fact]
    public async Task AnyUser_CanSuggestAHub_ButItDoesNotAppearOnListHubs()
    {
        var username = $"hub-suggester-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var suggestionName = $"Suggested Park {Guid.NewGuid():N}";

        var response = await SuggestHubAsync(token, suggestionName);
        response.EnsureSuccessStatusCode();
        var suggestion = await response.Content.ReadFromJsonAsync<HubDto>();
        Assert.Equal("Pending", suggestion!.Status);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", token));
        listResponse.EnsureSuccessStatusCode();
        var hubs = await listResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.DoesNotContain(hubs!, h => h.Id == suggestion.Id);
    }

    [Fact]
    public async Task NonAdmin_CannotListOrModerateSuggestions()
    {
        var username = $"hub-suggester-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-suggestions", token));
        Assert.Equal(HttpStatusCode.Forbidden, listResponse.StatusCode);

        var approveResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hub-suggestions/does-not-exist/approve", token));
        Assert.Equal(HttpStatusCode.Forbidden, approveResponse.StatusCode);
    }

    [Fact]
    public async Task Admin_CanApproveASuggestion_AndItThenAppearsOnListHubs()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var username = $"hub-suggester-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var suggestionName = $"Approved Park {Guid.NewGuid():N}";
        var suggestion = await (await SuggestHubAsync(token, suggestionName)).Content.ReadFromJsonAsync<HubDto>();

        var pendingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-suggestions", adminToken));
        pendingResponse.EnsureSuccessStatusCode();
        var pending = await pendingResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.Contains(pending!, h => h.Id == suggestion!.Id);

        var approveResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/hub-suggestions/{suggestion!.Id}/approve", adminToken));
        approveResponse.EnsureSuccessStatusCode();
        var approved = await approveResponse.Content.ReadFromJsonAsync<HubDto>();
        Assert.Equal("Approved", approved!.Status);
        // Approving moves the row from the Pending partition to Approved under the same id -
        // update tracking so DisposeAsync deletes it from the right partition.
        _hubIdToStatus[approved.Id] = approved.Status;

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", token));
        listResponse.EnsureSuccessStatusCode();
        var hubs = await listResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.Contains(hubs!, h => h.Id == suggestion.Id);
    }

    [Fact]
    public async Task Admin_CanRejectASuggestion_AndItIsGone()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var username = $"hub-suggester-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");
        var suggestion = await (await SuggestHubAsync(token, $"Rejected Park {Guid.NewGuid():N}")).Content.ReadFromJsonAsync<HubDto>();

        var rejectResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/hub-suggestions/{suggestion!.Id}", adminToken));
        Assert.Equal(HttpStatusCode.NoContent, rejectResponse.StatusCode);

        var pendingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-suggestions", adminToken));
        pendingResponse.EnsureSuccessStatusCode();
        var pending = await pendingResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.DoesNotContain(pending!, h => h.Id == suggestion.Id);
    }

    [Fact]
    public async Task Admin_CanMakeAFriendAdmin()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var username = $"future-admin-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var userResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/users/search?q=" + username, adminToken));
        userResponse.EnsureSuccessStatusCode();
        var matches = await userResponse.Content.ReadFromJsonAsync<List<UserSearchDto>>();
        var userId = Assert.Single(matches!).Id;

        var makeAdminResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/users/{userId}/make-admin", adminToken));
        makeAdminResponse.EnsureSuccessStatusCode();
        var updated = await makeAdminResponse.Content.ReadFromJsonAsync<UserResponseDto>();
        Assert.True(updated!.IsAdmin);

        _ = token; // only needed so the account exists to search for
    }

    [Fact]
    public async Task NonAdmin_CannotMakeAnotherUserAdmin()
    {
        var usernameA = $"hub-user-a-{Guid.NewGuid():N}";
        var usernameB = $"hub-user-b-{Guid.NewGuid():N}";
        var tokenA = await RegisterAndLoginAsync(usernameA, "correct-horse-battery-staple");
        await RegisterAndLoginAsync(usernameB, "correct-horse-battery-staple");

        var userResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/users/search?q=" + usernameB, tokenA));
        var matches = await userResponse.Content.ReadFromJsonAsync<List<UserSearchDto>>();
        var userId = Assert.Single(matches!).Id;

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/users/{userId}/make-admin", tokenA));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
    private record UserSearchDto(string Id, string Username, string? ProfilePictureUrl);
    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt, bool IsAdmin);
}
