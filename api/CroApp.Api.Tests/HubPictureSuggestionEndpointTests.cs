using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class HubPictureSuggestionEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    private const string DefaultAzuriteConnectionString = "UseDevelopmentStorage=true";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public HubPictureSuggestionEndpointTests(WebApplicationFactory<Program> factory)
    {
        var cosmosConnectionString = Environment.GetEnvironmentVariable("CosmosDb__ConnectionString")
            ?? DefaultEmulatorConnectionString;
        var blobConnectionString = Environment.GetEnvironmentVariable("BlobStorage__ConnectionString")
            ?? DefaultAzuriteConnectionString;

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["CosmosDb:UseEmulator"] = "true",
                    ["CosmosDb:ConnectionString"] = cosmosConnectionString,
                    ["CosmosDb:DatabaseName"] = "CroApp",
                    ["CosmosDb:UsersContainerName"] = "Users",
                    ["CosmosDb:WaypointsContainerName"] = "Waypoints",
                    ["CosmosDb:HubsContainerName"] = "Hubs",
                    ["CosmosDb:HubPictureSuggestionsContainerName"] = "HubPictureSuggestions",
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
                    ["BlobStorage:ConnectionString"] = blobConnectionString,
                    ["BlobStorage:HubPicturesContainerName"] = "hub-pictures",
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

    private async Task<HubDto> CreateHubAsync(string token, string name) =>
        (await (await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", token,
            new { Name = name, Latitude = 42.0, Longitude = -93.6, Category = "Landmark" })))
            .Content.ReadFromJsonAsync<HubDto>())!;

    private static MultipartFormDataContent BuildUpload(byte[] bytes, string contentType, string fileName = "photo.png")
    {
        var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(bytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        content.Add(fileContent, "file", fileName);
        return content;
    }

    private HttpRequestMessage SuggestPictureRequest(string token, string hubId, byte[] bytes, string contentType, string fileName = "photo.png")
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"/hubs/{hubId}/picture-suggestions")
        {
            Content = BuildUpload(bytes, contentType, fileName)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    [Fact]
    public async Task SuggestPicture_ThenAdminApproves_UpdatesHubProfilePictureUrl()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Test Plaza {Guid.NewGuid():N}");

        var suggesterUsername = $"hub-photo-suggester-{Guid.NewGuid():N}";
        var (_, suggesterToken) = await RegisterAndLoginAsync(suggesterUsername, SeedPassword);

        var suggestResponse = await _client.SendAsync(SuggestPictureRequest(suggesterToken, hub.Id, [1, 2, 3, 4], "image/png"));
        suggestResponse.EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Created, suggestResponse.StatusCode);
        var suggestion = await suggestResponse.Content.ReadFromJsonAsync<HubPictureSuggestionDto>();
        Assert.False(string.IsNullOrEmpty(suggestion!.BlobUrl));

        var pendingResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-picture-suggestions", adminToken));
        pendingResponse.EnsureSuccessStatusCode();
        var pending = await pendingResponse.Content.ReadFromJsonAsync<List<HubPictureSuggestionDto>>();
        Assert.Contains(pending!, s => s.Id == suggestion.Id && s.HubId == hub.Id);

        var approveResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/hub-picture-suggestions/{suggestion.Id}/approve", adminToken));
        approveResponse.EnsureSuccessStatusCode();
        var approvedHub = await approveResponse.Content.ReadFromJsonAsync<HubDto>();
        Assert.Equal(suggestion.BlobUrl, approvedHub!.ProfilePictureUrl);

        var pendingAfterResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-picture-suggestions", adminToken));
        var pendingAfter = await pendingAfterResponse.Content.ReadFromJsonAsync<List<HubPictureSuggestionDto>>();
        Assert.DoesNotContain(pendingAfter!, s => s.Id == suggestion.Id);

        var hubsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", suggesterToken));
        var hubs = await hubsResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.Equal(suggestion.BlobUrl, hubs!.Single(h => h.Id == hub.Id).ProfilePictureUrl);
    }

    [Fact]
    public async Task SuggestPicture_ThenAdminRejects_LeavesHubUnchanged()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Reject Plaza {Guid.NewGuid():N}");

        var suggesterUsername = $"hub-photo-suggester-{Guid.NewGuid():N}";
        var (_, suggesterToken) = await RegisterAndLoginAsync(suggesterUsername, SeedPassword);

        var suggestResponse = await _client.SendAsync(SuggestPictureRequest(suggesterToken, hub.Id, [1, 2, 3, 4], "image/png"));
        suggestResponse.EnsureSuccessStatusCode();
        var suggestion = await suggestResponse.Content.ReadFromJsonAsync<HubPictureSuggestionDto>();

        var rejectResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, $"/hub-picture-suggestions/{suggestion!.Id}", adminToken));
        Assert.Equal(HttpStatusCode.NoContent, rejectResponse.StatusCode);

        var pendingAfterResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-picture-suggestions", adminToken));
        var pendingAfter = await pendingAfterResponse.Content.ReadFromJsonAsync<List<HubPictureSuggestionDto>>();
        Assert.DoesNotContain(pendingAfter!, s => s.Id == suggestion.Id);

        var hubsResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hubs", suggesterToken));
        var hubs = await hubsResponse.Content.ReadFromJsonAsync<List<HubDto>>();
        Assert.Null(hubs!.Single(h => h.Id == hub.Id).ProfilePictureUrl);
    }

    [Fact]
    public async Task NonAdmin_CannotListOrModeratePictureSuggestions()
    {
        var username = $"hub-photo-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var listResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/hub-picture-suggestions", token));
        Assert.Equal(HttpStatusCode.Forbidden, listResponse.StatusCode);

        var approveResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hub-picture-suggestions/does-not-exist/approve", token));
        Assert.Equal(HttpStatusCode.Forbidden, approveResponse.StatusCode);

        var rejectResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Delete, "/hub-picture-suggestions/does-not-exist", token));
        Assert.Equal(HttpStatusCode.Forbidden, rejectResponse.StatusCode);
    }

    [Fact]
    public async Task SuggestPicture_ForNonexistentHub_ReturnsNotFound()
    {
        var username = $"hub-photo-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(SuggestPictureRequest(token, "does-not-exist", [1, 2, 3], "image/png"));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SuggestPicture_WithUnsupportedContentType_ReturnsBadRequest()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Bad Type Plaza {Guid.NewGuid():N}");

        var username = $"hub-photo-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(SuggestPictureRequest(token, hub.Id, [1, 2, 3], "application/pdf", "file.pdf"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SuggestPicture_TooLarge_ReturnsBadRequest()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Too Large Plaza {Guid.NewGuid():N}");

        var username = $"hub-photo-user-{Guid.NewGuid():N}";
        var (_, token) = await RegisterAndLoginAsync(username, SeedPassword);

        var response = await _client.SendAsync(SuggestPictureRequest(token, hub.Id, new byte[6 * 1024 * 1024], "image/png"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SuggestPicture_WithoutToken_ReturnsUnauthorized()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Anon Plaza {Guid.NewGuid():N}");

        var request = new HttpRequestMessage(HttpMethod.Post, $"/hubs/{hub.Id}/picture-suggestions")
        {
            Content = BuildUpload([1, 2, 3], "image/png")
        };

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UserResponseDto(string Id, string Username, string Email);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string Category, string? ProfilePictureUrl);
    private record HubPictureSuggestionDto(string Id, string HubId, string SuggestedByUserId, string BlobUrl, DateTimeOffset CreatedAt);
}
