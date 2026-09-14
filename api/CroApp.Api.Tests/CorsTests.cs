using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class CorsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public CorsTests(WebApplicationFactory<Program> factory)
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

    [Fact]
    public async Task PreflightRequest_FromAnyLocalhostPort_IsAllowed()
    {
        // Mirrors exactly what a browser sends before a real POST /users or /login -
        // this is the request that was failing (issue #24) before CORS was configured.
        var request = new HttpRequestMessage(HttpMethod.Options, "/users");
        request.Headers.Add("Origin", "http://localhost:53629");
        request.Headers.Add("Access-Control-Request-Method", "POST");
        request.Headers.Add("Access-Control-Request-Headers", "Content-Type");

        var response = await _client.SendAsync(request);

        Assert.True(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    [Fact]
    public async Task PreflightRequest_WithAuthorizationHeader_IsAllowed()
    {
        // Mirrors what a browser sends before an authenticated PUT/GET /waypoint request -
        // Authorization isn't a CORS "simple" header, so it shows up in
        // Access-Control-Request-Headers and must pass the preflight check.
        var request = new HttpRequestMessage(HttpMethod.Options, "/waypoint");
        request.Headers.Add("Origin", "http://localhost:53629");
        request.Headers.Add("Access-Control-Request-Method", "GET");
        request.Headers.Add("Access-Control-Request-Headers", "authorization");

        var response = await _client.SendAsync(request);

        Assert.True(response.Headers.Contains("Access-Control-Allow-Origin"));
    }
}

public class ProdCorsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string AllowedOrigin = "https://cro-app.example.com";

    private readonly HttpClient _client;

    public ProdCorsTests(WebApplicationFactory<Program> factory)
    {
        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Production");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                // Program.cs's container-provisioning startup block now runs in every
                // environment (see TECH_DEBT.md), not just Development, so this fixture needs
                // the full CosmosDb/BlobStorage key set - same as every other fixture uses via
                // TestConfig.Build() - not just the Cors/Jwt keys this test itself exercises.
                var testConfig = TestConfig.Build();
                testConfig["Cors:AllowedOrigin"] = AllowedOrigin;
                config.AddInMemoryCollection(testConfig);
            });
        });

        _client = configuredFactory.CreateClient();
    }

    [Fact]
    public async Task PreflightRequest_FromConfiguredOrigin_IsAllowed()
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/users");
        request.Headers.Add("Origin", AllowedOrigin);
        request.Headers.Add("Access-Control-Request-Method", "POST");
        request.Headers.Add("Access-Control-Request-Headers", "Content-Type");

        var response = await _client.SendAsync(request);

        Assert.True(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    [Fact]
    public async Task PreflightRequest_FromUnconfiguredOrigin_IsRejected()
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/users");
        request.Headers.Add("Origin", "https://not-the-real-site.example.com");
        request.Headers.Add("Access-Control-Request-Method", "POST");
        request.Headers.Add("Access-Control-Request-Headers", "Content-Type");

        var response = await _client.SendAsync(request);

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }
}
