using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace CroApp.Api.Tests;

public class BirdComposeEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

    // Seeded by Program.cs's dev-only startup step, same fixed dev password every run.
    private const string SeedPassword = "correct-horse-battery-staple";

    private readonly HttpClient _client;

    public BirdComposeEndpointTests(WebApplicationFactory<Program> factory)
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
                    ["CosmosDb:ReactionsContainerName"] = "Reactions",
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

    private async Task<WaypointDto> CreateNestAsync(string token, string name, double lat = 42.0, double lng = -93.5, bool isPublic = false)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/waypoints", token,
            new { Name = name, Latitude = lat, Longitude = lng, IsPublic = isPublic }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<WaypointDto>())!;
    }

    private async Task<HubDto> CreateHubAsync(string adminToken, string name, double lat = 42.03, double lng = -93.63)
    {
        var response = await _client.SendAsync(AuthedRequest(HttpMethod.Post, "/hubs", adminToken,
            new { Name = name, Latitude = lat, Longitude = lng, Category = "Library" }));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<HubDto>())!;
    }

    private Task<HttpResponseMessage> ComposeBirdAsync(
        string? token,
        string type,
        string name,
        string originNestId,
        string destinationId,
        string? content = null,
        (byte[] Bytes, string ContentType, string Filename)? media = null,
        bool? isPublic = null)
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
        if (isPublic is not null)
        {
            form.Add(new StringContent(isPublic.Value.ToString()), "isPublic");
        }
        if (media is not null)
        {
            var fileContent = new ByteArrayContent(media.Value.Bytes);
            fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(media.Value.ContentType);
            form.Add(fileContent, "file", media.Value.Filename);
        }
        request.Content = form;
        return _client.SendAsync(request);
    }

    private static readonly byte[] TinyImageBytes = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4];
    private static readonly byte[] TinyAudioBytes = [0x49, 0x44, 0x33, 1, 2, 3, 4];

    [Fact]
    public async Task ComposeCroBird_WithText_Succeeds()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Cro", "Speedy", origin.Id, dest.Id, content: "hello");
        response.EnsureSuccessStatusCode();
        var bird = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.True(bird!.IsTraveling);
        Assert.Equal("hello", bird.Content);
        Assert.Equal("Cro", bird.Type);
        Assert.Equal(origin.Id, bird.NestFromId);
        Assert.Equal(dest.Id, bird.NestToId);
    }

    [Fact]
    public async Task ComposeCroBird_WithoutContent_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Cro", "Speedy", origin.Id, dest.Id);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ComposeParrotBird_WithAudioFile_Succeeds()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Parrot", "Squawks", origin.Id, dest.Id,
            media: (TinyAudioBytes, "audio/mpeg", "clip.mp3"));
        response.EnsureSuccessStatusCode();
        var bird = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.NotNull(bird!.AudioUrl);
        Assert.Null(bird.ImageUrl);
        Assert.Null(bird.Content);
    }

    [Fact]
    public async Task ComposeParrotBird_WithoutFile_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Parrot", "Squawks", origin.Id, dest.Id);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ComposeParrotBird_WithTextInstead_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Parrot", "Squawks", origin.Id, dest.Id, content: "text not allowed");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ComposePigeonBird_WithImageFile_Succeeds()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Pigeon", "Slowpoke", origin.Id, dest.Id,
            media: (TinyImageBytes, "image/png", "photo.png"));
        response.EnsureSuccessStatusCode();
        var bird = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.NotNull(bird!.ImageUrl);
        Assert.Null(bird.AudioUrl);
    }

    [Fact]
    public async Task ComposeRavenBird_RequiresBothTextAndImage()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var textOnly = await ComposeBirdAsync(token, "Raven", "Messenger", origin.Id, dest.Id, content: "hi");
        Assert.Equal(HttpStatusCode.BadRequest, textOnly.StatusCode);

        var imageOnly = await ComposeBirdAsync(token, "Raven", "Messenger", origin.Id, dest.Id,
            media: (TinyImageBytes, "image/png", "photo.png"));
        Assert.Equal(HttpStatusCode.BadRequest, imageOnly.StatusCode);

        var both = await ComposeBirdAsync(token, "Raven", "Messenger", origin.Id, dest.Id,
            content: "hi", media: (TinyImageBytes, "image/png", "photo.png"));
        both.EnsureSuccessStatusCode();
        var bird = await both.Content.ReadFromJsonAsync<BirdDto>();
        Assert.Equal("hi", bird!.Content);
        Assert.NotNull(bird.ImageUrl);
    }

    [Fact]
    public async Task ComposeBird_UnknownType_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        var response = await ComposeBirdAsync(token, "Eagle", "Nope", origin.Id, dest.Id, content: "hi");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ComposeBird_FromAnotherUsersNest_ReturnsNotFound()
    {
        var tokenA = await RegisterAndLoginAsync($"compose-a-{Guid.NewGuid():N}", SeedPassword);
        var tokenB = await RegisterAndLoginAsync($"compose-b-{Guid.NewGuid():N}", SeedPassword);
        var bNest = await CreateNestAsync(tokenB, "B's Nest", isPublic: false);
        var aDest = await CreateNestAsync(tokenA, "A's Nest", 50.0, 50.0, isPublic: false);

        var response = await ComposeBirdAsync(tokenA, "Cro", "Sneaky", bNest.Id, aDest.Id, content: "hi");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ComposeBird_ToHub_Succeeds()
    {
        var adminToken = await LoginAsync("Admin 1", SeedPassword);
        var hub = await CreateHubAsync(adminToken, $"Test Library {Guid.NewGuid():N}");

        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);

        var response = await ComposeBirdAsync(token, "Cro", "Off to the library", origin.Id, hub.Id, content: "see you there");
        response.EnsureSuccessStatusCode();
        var bird = await response.Content.ReadFromJsonAsync<BirdDto>();

        Assert.Equal(hub.Id, bird!.NestToId);
        Assert.True(bird.IsTraveling);
    }

    [Fact]
    public async Task ComposingASixthBird_ReturnsConflict()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);
        var dest = await CreateNestAsync(token, "Away", 50.0, 50.0, isPublic: true);

        for (var i = 0; i < 5; i++)
        {
            var response = await ComposeBirdAsync(token, "Cro", $"Bird {i}", origin.Id, dest.Id, content: "hi");
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        }

        var sixth = await ComposeBirdAsync(token, "Cro", "One Too Many", origin.Id, dest.Id, content: "hi");
        Assert.Equal(HttpStatusCode.Conflict, sixth.StatusCode);
    }

    [Fact]
    public async Task ComposeBird_SameOriginAndDestination_ReturnsBadRequest()
    {
        var token = await RegisterAndLoginAsync($"compose-user-{Guid.NewGuid():N}", SeedPassword);
        var origin = await CreateNestAsync(token, "Home", isPublic: false);

        var response = await ComposeBirdAsync(token, "Cro", "Nowhere", origin.Id, origin.Id, content: "hi");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ComposeBird_WithoutToken_ReturnsUnauthorized()
    {
        var response = await ComposeBirdAsync(null, "Cro", "Nope", "some-id", "other-id", content: "hi");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private record LoginResponseDto(string Token, DateTimeOffset ExpiresAt);
    private record WaypointDto(string Id, string UserId, string Name, double Latitude, double Longitude, DateTimeOffset UpdatedAt, bool IsPublic);
    private record HubDto(string Id, string Name, double Latitude, double Longitude, string Status, string CreatedByUserId, DateTimeOffset CreatedAt, string? Category, string? ProfilePictureUrl);
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
