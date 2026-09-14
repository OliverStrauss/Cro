using System.Net;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class HealthEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(WebApplicationFactory<Program> factory)
    {
        // Was its own hand-rolled partial dictionary (just Cosmos connection/Jwt keys),
        // unlike every other fixture in this project - relying on appsettings.json to supply
        // every other CosmosDb/BlobStorage container-name key Program.cs's dev-only startup
        // provisioning reads unconditionally. See TestConfig's own doc comment: that's exactly
        // the "fixture config gap" pattern every other fixture already avoids by using
        // TestConfig.Build(), which lists the full key set explicitly instead of depending on
        // appsettings.json actually being resolved the same way in every test environment.
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
    public async Task Health_ReturnsOk()
    {
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
