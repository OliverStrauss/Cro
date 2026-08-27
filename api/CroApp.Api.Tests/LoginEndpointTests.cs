using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class LoginEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    private readonly HttpClient _client;
    private readonly string _connectionString;

    public LoginEndpointTests(WebApplicationFactory<Program> factory)
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

    // Seeds a raw Cosmos document with no passwordHash field at all - reproduces legacy
    // documents created before the Password field existed (see issue #16).
    private async Task SeedPasswordlessUserAsync(string username)
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
        var container = cosmosClient.GetContainer("CroApp", "Users");

        await container.CreateItemAsync(new
        {
            id = Guid.NewGuid().ToString(),
            username,
            email = $"{username}@example.com",
            createdAt = DateTimeOffset.UtcNow
        });
    }

    private async Task<string> RegisterUserAsync(string username, string password)
    {
        var createResponse = await _client.PostAsJsonAsync("/users",
            new { Username = username, Email = $"{username}@example.com", Password = password });
        createResponse.EnsureSuccessStatusCode();
        return username;
    }

    [Fact]
    public async Task Login_WithCorrectPassword_ReturnsToken()
    {
        var username = $"login-user-{Guid.NewGuid():N}";
        const string password = "correct-horse-battery-staple";
        await RegisterUserAsync(username, password);

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = password });
        loginResponse.EnsureSuccessStatusCode();

        var body = await loginResponse.Content.ReadFromJsonAsync<LoginResponseDto>();
        Assert.NotNull(body);
        Assert.False(string.IsNullOrWhiteSpace(body!.Token));
        Assert.True(body.ExpiresAt > DateTimeOffset.UtcNow);
    }

    [Fact]
    public async Task Login_WithWrongPassword_ReturnsUnauthorized()
    {
        var username = $"login-user-{Guid.NewGuid():N}";
        await RegisterUserAsync(username, "correct-horse-battery-staple");

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "wrong-password" });

        Assert.Equal(HttpStatusCode.Unauthorized, loginResponse.StatusCode);
    }

    [Fact]
    public async Task Login_WithUnknownUsername_ReturnsUnauthorized()
    {
        var loginResponse = await _client.PostAsJsonAsync("/login",
            new { Username = $"nobody-{Guid.NewGuid():N}", Password = "whatever" });

        Assert.Equal(HttpStatusCode.Unauthorized, loginResponse.StatusCode);
    }

    [Fact]
    public async Task Login_WithNoPasswordHashOnRecord_ReturnsUnauthorizedNotServerError()
    {
        var username = $"legacy-user-{Guid.NewGuid():N}";
        await SeedPasswordlessUserAsync(username);

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "whatever" });

        Assert.Equal(HttpStatusCode.Unauthorized, loginResponse.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
}
