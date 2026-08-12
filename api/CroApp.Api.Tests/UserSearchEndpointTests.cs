using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class UserSearchEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;

    public UserSearchEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:HubsContainerName"] = "Hubs",
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

    private static HttpRequestMessage AuthedRequest(HttpMethod method, string uri, string? token)
    {
        var request = new HttpRequestMessage(method, uri);
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
        return request;
    }

    [Fact]
    public async Task Search_ReturnsCaseInsensitivePrefixMatches_ExcludingTheCaller()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, searcherToken) = await RegisterAndLoginAsync($"searcher-{suffix}", "correct-horse-battery-staple");
        var (matchId, _) = await RegisterAndLoginAsync($"alice-{suffix}", "correct-horse-battery-staple");
        await RegisterAndLoginAsync($"bob-{suffix}", "correct-horse-battery-staple");

        // Mixed-case query against a lowercase username - the search must be case-insensitive.
        var response = await _client.SendAsync(
            AuthedRequest(HttpMethod.Get, $"/users/search?q=ALICE-{suffix}", searcherToken));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<List<UserSearchResultDto>>();
        Assert.NotNull(results);
        Assert.Contains(results!, r => r.Id == matchId);
        Assert.DoesNotContain(results!, r => r.Username.StartsWith("bob-", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Search_NeverReturnsTheCallerThemselves()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var username = $"self-search-{suffix}";
        var (selfId, token) = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/users/search?q={username}", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<List<UserSearchResultDto>>();
        Assert.NotNull(results);
        Assert.DoesNotContain(results!, r => r.Id == selfId);
    }

    [Fact]
    public async Task Search_WithoutAToken_IsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/users/search?q=a", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Search_WithAnEmptyQuery_ReturnsNoResults()
    {
        var (_, token) = await RegisterAndLoginAsync($"empty-query-{Guid.NewGuid():N}", "correct-horse-battery-staple");

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/users/search?q=", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<List<UserSearchResultDto>>();
        Assert.NotNull(results);
        Assert.Empty(results!);
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UserSearchResultDto(string Id, string Username, string? ProfilePictureUrl);
}
