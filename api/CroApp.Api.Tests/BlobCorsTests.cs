using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BlobCorsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    private const string DefaultAzuriteConnectionString = "UseDevelopmentStorage=true";

    private readonly HttpClient _client;

    public BlobCorsTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
                    ["BlobStorage:ConnectionString"] = blobConnectionString,
                    ["BlobStorage:ProfilePicturesContainerName"] = "profile-pictures",
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

    private static HttpRequestMessage UploadRequest(string token, byte[] bytes, string contentType, string fileName = "avatar.png")
    {
        var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(bytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        content.Add(fileContent, "file", fileName);

        var request = new HttpRequestMessage(HttpMethod.Put, "/profile/picture") { Content = content };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    [Fact]
    public async Task BlobGetRequest_WithOriginHeader_ReturnsAccessControlAllowOrigin()
    {
        var username = $"cors-user-{Guid.NewGuid():N}";
        var token = await RegisterAndLoginAsync(username, "correct-horse-battery-staple");

        var uploadResponse = await _client.SendAsync(UploadRequest(token, [1, 2, 3], "image/png"));
        uploadResponse.EnsureSuccessStatusCode();
        var uploadBody = await uploadResponse.Content.ReadFromJsonAsync<UploadResponseDto>();

        // Mirrors exactly what the browser does: a direct GET to the blob URL (not
        // through this API) with an Origin header, the same request Flutter Web's
        // NetworkImage sends - unlike this API's own DevCorsPolicy, Blob Storage CORS
        // has to be configured separately, so this bypasses the API entirely on purpose.
        using var rawClient = new HttpClient();
        var request = new HttpRequestMessage(HttpMethod.Get, uploadBody!.ProfilePictureUrl);
        request.Headers.Add("Origin", "http://localhost:53629");

        var response = await rawClient.SendAsync(request);

        Assert.True(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record UploadResponseDto(string ProfilePictureUrl);
}
