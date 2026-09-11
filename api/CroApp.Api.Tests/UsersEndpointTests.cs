using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class UsersEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public UsersEndpointTests(WebApplicationFactory<Program> factory)
    {
        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build());
            });
        });

        _client = configuredFactory.CreateClient();
    }

    // Fixed, non-secret test-only signing key - Program.cs wires up JWT bearer auth
    // unconditionally at startup, so every test host needs a valid key even if the
    // test itself never calls /login. Never use this constant outside tests.
    internal const string TestJwtSigningKey = "test-only-signing-key-not-used-in-any-real-environment-32bytes+";

    [Fact]
    public async Task CreateThenGetUser_RoundTripsSuccessfully()
    {
        var createRequest = new { Username = $"test-user-{Guid.NewGuid():N}", Email = "test@example.com", Password = "correct-horse-battery-staple" };

        var createResponse = await _client.PostAsJsonAsync("/users", createRequest);
        createResponse.EnsureSuccessStatusCode();

        var created = await createResponse.Content.ReadFromJsonAsync<UserResponse>();
        Assert.NotNull(created);
        Assert.Equal(createRequest.Username, created!.Username);

        var getResponse = await _client.GetAsync($"/users/{created.Id}");
        getResponse.EnsureSuccessStatusCode();

        var fetched = await getResponse.Content.ReadFromJsonAsync<UserResponse>();
        Assert.NotNull(fetched);
        Assert.Equal(created.Id, fetched!.Id);
        Assert.Equal(created.Username, fetched.Username);
    }

    [Fact]
    public async Task CreateUser_WithDuplicateUsername_ReturnsConflictAndDoesNotCreateSecondUser()
    {
        var username = $"test-user-{Guid.NewGuid():N}";
        var createRequest = new { Username = username, Email = "first@example.com", Password = "correct-horse-battery-staple" };
        var firstResponse = await _client.PostAsJsonAsync("/users", createRequest);
        firstResponse.EnsureSuccessStatusCode();

        var duplicateRequest = new { Username = username, Email = "second@example.com", Password = "another-password" };
        var duplicateResponse = await _client.PostAsJsonAsync("/users", duplicateRequest);

        Assert.Equal(System.Net.HttpStatusCode.Conflict, duplicateResponse.StatusCode);
    }

    private record UserResponse(string Id, string Username, string Email, DateTimeOffset CreatedAt);
}
