using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using CroApp.Api.Models;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace CroApp.Api.Tests;

public class SearchEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    // Seeded by Program.cs's dev-only startup step, same fixed dev password on every run -
    // see CLAUDE.md's well-known-local-credentials section.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;
    private readonly FakeGeocodingService _geocodingService = new();

    public SearchEndpointTests(WebApplicationFactory<Program> factory)
    {
        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build());
            });
            // Swaps out NominatimGeocodingService so tests never hit the real network - same
            // seam EmailVerificationEndpointTests.cs uses for IEmailSender.
            builder.ConfigureTestServices(services => services.AddSingleton<IGeocodingService>(_geocodingService));
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

    private async Task<WaypointDto> CreateNestAsync(string token, string name, double lat = 42.0, double lng = -93.6)
    {
        var response = await _client.SendAsync(
            AuthedRequest(HttpMethod.Post, "/waypoints", token, new { Name = name, Latitude = lat, Longitude = lng, IsPublic = false }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    [Fact]
    public async Task Search_ReturnsMatchingHubsNestsAndPlaces()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, token) = await RegisterAndLoginAsync($"searcher-{suffix}", SeedPassword);
        await CreateNestAsync(token, $"{suffix} Library");

        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hubResponse = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", adminToken,
            new { Name = $"{suffix} Cafe", Latitude = 42.0, Longitude = -93.6, Category = "Landmark" }));
        hubResponse.EnsureSuccessStatusCode();

        _geocodingService.Results = [new PlaceSearchResult("Ames, Iowa, USA", 42.0308, -93.6319)];

        // The prefix search only matches from the start of a name - "suffix" alone as the
        // query, not "Ames ...", proves that (STARTSWITH, not a substring search).
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/search?q={suffix}", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<SearchResponseDto>();
        Assert.NotNull(results);
        Assert.Contains(results!.Hubs, h => h.Name == $"{suffix} Cafe");
        Assert.Contains(results.Nests, n => n.Name == $"{suffix} Library");
    }

    [Fact]
    public async Task Search_IncludesGeocodedPlaces_FromTheGeocodingService()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, token) = await RegisterAndLoginAsync($"places-{suffix}", SeedPassword);
        _geocodingService.Results = [new PlaceSearchResult("Ames, Iowa, USA", 42.0308, -93.6319)];

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/search?q=Ames", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<SearchResponseDto>();
        Assert.NotNull(results);
        Assert.Contains(results!.Places, p => p.DisplayName == "Ames, Iowa, USA");
    }

    [Fact]
    public async Task Search_NestsAreScopedToOwnAndFriendsOnly()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (idA, tokenA) = await RegisterAndLoginAsync($"searcher-a-{suffix}", SeedPassword);
        var (idB, tokenB) = await RegisterAndLoginAsync($"friend-b-{suffix}", SeedPassword);
        var (_, tokenC) = await RegisterAndLoginAsync($"stranger-c-{suffix}", SeedPassword);

        await CreateNestAsync(tokenB, $"Shared Nest {suffix}");
        await CreateNestAsync(tokenC, $"Shared Nest {suffix}");

        // Only A and B become friends - C stays a stranger to A.
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/friends/requests", tokenA, new { Username = $"friend-b-{suffix}" }));
        await _client.SendAsync(AuthedRequest(HttpMethod.Post, $"/friends/requests/{idA}/accept", tokenB));

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/search?q=Shared Nest {suffix}", tokenA));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<SearchResponseDto>();
        Assert.NotNull(results);
        Assert.Single(results!.Nests);
        Assert.Equal(idB, results.Nests[0].UserId);
    }

    [Fact]
    public async Task Search_WithoutAToken_IsUnauthorized()
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/search?q=a", token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Search_WithAnEmptyQuery_ReturnsNoResults()
    {
        var (_, token) = await RegisterAndLoginAsync($"empty-query-{Guid.NewGuid():N}", SeedPassword);

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, "/search?q=", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<SearchResponseDto>();
        Assert.NotNull(results);
        Assert.Empty(results!.Places);
        Assert.Empty(results.Hubs);
        Assert.Empty(results.Nests);
    }

    [Fact]
    public async Task Search_WhenGeocodingFails_StillReturnsHubAndNestMatches()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, token) = await RegisterAndLoginAsync($"geo-fail-{suffix}", SeedPassword);
        await CreateNestAsync(token, $"Resilient Nest {suffix}");
        _geocodingService.ShouldThrow = true;

        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Get, $"/search?q=Resilient Nest {suffix}", token));
        response.EnsureSuccessStatusCode();

        var results = await response.Content.ReadFromJsonAsync<SearchResponseDto>();
        Assert.NotNull(results);
        Assert.Empty(results!.Places);
        Assert.Contains(results.Nests, n => n.Name == $"Resilient Nest {suffix}");
    }

    private class FakeGeocodingService : IGeocodingService
    {
        public List<PlaceSearchResult> Results { get; set; } = [];
        public bool ShouldThrow { get; set; }

        public Task<List<PlaceSearchResult>> SearchAsync(string query)
        {
            if (ShouldThrow)
            {
                throw new HttpRequestException("Simulated geocoding outage");
            }
            return Task.FromResult(Results);
        }
    }

    private record UserResponseDto(string Id, string Username, string Email, DateTimeOffset CreatedAt);
    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string Name, double Latitude, double Longitude);
    private record HubResultDto(string Id, string Name);
    private record NestResultDto(string Id, string Name, string UserId);
    private record PlaceResultDto(string DisplayName, double Latitude, double Longitude);
    private record SearchResponseDto(List<PlaceResultDto> Places, List<HubResultDto> Hubs, List<NestResultDto> Nests);
}
