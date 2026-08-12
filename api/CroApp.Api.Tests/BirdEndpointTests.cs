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
                    ["CosmosDb:HubsContainerName"] = "Hubs",
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

    private async Task<WaypointDto> CreateWaypointAsync(string token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private Task<HttpResponseMessage> ComposeBirdAsync(
        string? token,
        string type,
        string name,
        string originNestId,
        string destinationId,
        string? content = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/birds/compose");
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
        var form = new MultipartFormDataContent
        {
            { new StringContent(type), "type" },
            { new StringContent(name), "name" },
            { new StringContent(originNestId), "originNestId" },
            { new StringContent(destinationId), "destinationId" },
        };
        if (content is not null)
        {
            form.Add(new StringContent(content), "content");
        }
        request.Content = form;
        return _client.SendAsync(request);
    }

    [Fact]
    public async Task ListBirds_ForNewUser_ReturnsEmptyList()
    {
        var username = $"bird-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var response = await ListBirdsAsync(token);
        response.EnsureSuccessStatusCode();
        var birds = await response.Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Empty(birds!);
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

        var aOrigin = await CreateWaypointAsync(tokenA, "A's Nest", isPublic: false);
        var aDest = await CreateWaypointAsync(tokenA, "A's Away", 43.0, -94.0, isPublic: true);
        (await ComposeBirdAsync(tokenA, "Cro", "A's Bird", aOrigin.Id, aDest.Id, content: "hi")).EnsureSuccessStatusCode();

        var birdsA = await (await ListBirdsAsync(tokenA)).Content.ReadFromJsonAsync<List<BirdDto>>();
        var birdsB = await (await ListBirdsAsync(tokenB)).Content.ReadFromJsonAsync<List<BirdDto>>();

        Assert.Single(birdsA!);
        Assert.Empty(birdsB!);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
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
        DateTimeOffset UpdatedAt,
        string? AudioUrl,
        string? ImageUrl,
        string? ProfilePictureUrl,
        bool IsPublic);
}
