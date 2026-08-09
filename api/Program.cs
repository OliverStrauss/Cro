using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using User = CroApp.Api.Models.User;

const string DevCorsPolicy = "DevCorsPolicy";

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

// Flutter web's dev server runs on a randomly-assigned localhost port each run, so a
// fixed-origin allow-list isn't practical here. Development-only, same pattern as the
// emulator TLS bypass and container auto-provisioning below - production needs a real
// allow-list of the deployed web app's actual origin, not yet relevant since there's no
// prod deployment.
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy(DevCorsPolicy, policy =>
        {
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        });
    });
}

builder.Services.Configure<CosmosDbOptions>(builder.Configuration.GetSection("CosmosDb"));
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));
builder.Services.Configure<BlobStorageOptions>(builder.Configuration.GetSection("BlobStorage"));

builder.Services.AddSingleton(sp =>
{
    var opts = sp.GetRequiredService<IOptions<CosmosDbOptions>>().Value;
    var clientOptions = new CosmosClientOptions
    {
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    };

    // The emulator serves a self-signed cert. Only bypass validation when explicitly
    // configured to use the emulator, so this never applies to a real Cosmos endpoint.
    if (opts.UseEmulator)
    {
        clientOptions.HttpClientFactory = () => new HttpClient(new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        });
        clientOptions.ConnectionMode = ConnectionMode.Gateway;
    }

    return new CosmosClient(opts.ConnectionString, clientOptions);
});

builder.Services.AddSingleton(sp =>
{
    var opts = sp.GetRequiredService<IOptions<BlobStorageOptions>>().Value;
    return new BlobServiceClient(opts.ConnectionString);
});

builder.Services.AddScoped<IUserRepository, CosmosUserRepository>();
builder.Services.AddScoped<IWaypointRepository, CosmosWaypointRepository>();
builder.Services.AddScoped<IWaypointService, WaypointService>();
builder.Services.AddScoped<IBirdRepository, CosmosBirdRepository>();
builder.Services.AddScoped<IBirdService, BirdService>();
builder.Services.AddScoped<IFriendService, FriendService>();
builder.Services.AddScoped<IProfilePictureService, ProfilePictureService>();

var jwtSection = builder.Configuration.GetSection("Jwt");
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // Without this, "sub"/"unique_name" claims JwtTokenService issues get silently
        // remapped to legacy ClaimTypes.NameIdentifier/Name URIs, so reading them back via
        // JwtRegisteredClaimNames.Sub would return null instead of the actual user id.
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSection["Issuer"],
            ValidAudience = jwtSection["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSection["SigningKey"] ?? string.Empty))
        };
    });
builder.Services.AddAuthorization();

var app = builder.Build();

// Provision the Users container on startup for local/emulator convenience only.
// Production container creation is a deliberate one-time step, not something the API does on every boot.
if (app.Environment.IsDevelopment())
{
    using var scope = app.Services.CreateScope();
    var client = scope.ServiceProvider.GetRequiredService<CosmosClient>();
    var opts = scope.ServiceProvider.GetRequiredService<IOptions<CosmosDbOptions>>().Value;
    var database = await client.CreateDatabaseIfNotExistsAsync(opts.DatabaseName);
    await database.Database.CreateContainerIfNotExistsAsync(opts.UsersContainerName, "/id");
    // /userId, not /id - a user can have up to 5 waypoints now, so the owning user's id is
    // the partition key (one partition per user) while each waypoint gets its own generated
    // id. CreateContainerIfNotExistsAsync is a no-op against an existing container, so a
    // pre-existing local "Waypoints" container from before this change needs a one-time
    // manual drop (see CLAUDE.md's Local Cosmos DB Emulator section) - CI is unaffected since
    // its emulator container is fresh every run.
    await database.Database.CreateContainerIfNotExistsAsync(opts.WaypointsContainerName, "/userId");
    // Same /userId partition-key reasoning as Waypoints: every user has a fixed set of
    // birds, so scoping by owner keeps GET /birds' lazy-provisioning check and the
    // nest-assignment update both single-partition operations.
    await database.Database.CreateContainerIfNotExistsAsync(opts.BirdsContainerName, "/userId");

    var blobClient = scope.ServiceProvider.GetRequiredService<BlobServiceClient>();
    var blobOpts = scope.ServiceProvider.GetRequiredService<IOptions<BlobStorageOptions>>().Value;
    // PublicAccessType.Blob (public read for blobs, no container listing) keeps uploaded
    // pictures fetchable via a plain URL without SAS tokens - fine for local/dev, but a
    // real deployment needs real access control here before this container goes live.
    await blobClient.GetBlobContainerClient(blobOpts.ProfilePicturesContainerName)
        .CreateIfNotExistsAsync(PublicAccessType.Blob);

    // Blob Storage CORS is entirely separate from ASP.NET Core's CORS middleware
    // (DevCorsPolicy above only covers requests hitting this API, not the browser's
    // direct fetch to Azurite/Blob Storage for profile picture images) - the browser's
    // CORS-mode fetch for NetworkImage needs Access-Control-Allow-Origin on the blob
    // response itself. Development-only, same pattern as DevCorsPolicy and the emulator
    // TLS bypass - production needs its own real Azure Storage account CORS config,
    // not yet relevant since there's no prod deployment.
    //
    // SetPropertiesAsync replaces the whole properties document, not just the fields you
    // set - sending a fresh BlobServiceProperties with everything else null/default gets
    // rejected outright (400), so this reads the existing properties first and only adds
    // Cors to them.
    var serviceProperties = (await blobClient.GetPropertiesAsync()).Value;
    serviceProperties.Cors =
    [
        new BlobCorsRule
        {
            AllowedOrigins = "*",
            AllowedMethods = "GET",
            AllowedHeaders = "*",
            ExposedHeaders = "*",
            MaxAgeInSeconds = 3600
        }
    ];
    await blobClient.SetPropertiesAsync(serviceProperties);
}

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseCors(DevCorsPolicy);
}

app.UseAuthentication();
app.UseAuthorization();

app.MapPost("/users", async (CreateUserRequest req, IUserRepository repo) =>
{
    var hasher = new PasswordHasher<User>();
    var user = new User(Guid.NewGuid().ToString(), req.Username, req.Email, DateTimeOffset.UtcNow, PasswordHash: "", Friends: []);
    var hashedUser = user with { PasswordHash = hasher.HashPassword(user, req.Password) };
    var created = await repo.CreateAsync(hashedUser);
    return Results.Created($"/users/{created.Id}", created.ToResponse());
})
.WithName("CreateUser");

app.MapGet("/users/{id}", async (string id, IUserRepository repo) =>
    await repo.GetByIdAsync(id) is { } user ? Results.Ok(user.ToResponse()) : Results.NotFound())
.WithName("GetUserById");

app.MapPost("/login", async (LoginRequest req, IUserRepository repo, IOptions<JwtOptions> jwtOpts) =>
{
    var user = await repo.GetByUsernameAsync(req.Username);
    if (user is null || string.IsNullOrEmpty(user.PasswordHash))
    {
        return Results.Unauthorized();
    }

    var hasher = new PasswordHasher<User>();
    var result = hasher.VerifyHashedPassword(user, user.PasswordHash, req.Password);
    if (result == PasswordVerificationResult.Failed)
    {
        return Results.Unauthorized();
    }

    var (token, expiresAt) = JwtTokenService.GenerateToken(user, jwtOpts.Value);
    return Results.Ok(new LoginResponse(token, expiresAt));
})
.WithName("Login");

app.MapGet("/waypoints", async (ClaimsPrincipal principal, IWaypointService waypointService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(await waypointService.ListAsync(userId));
})
.RequireAuthorization()
.WithName("ListWaypoints");

app.MapPost("/waypoints", async (SetWaypointRequest req, ClaimsPrincipal principal, IWaypointService waypointService, IBirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        var saved = await waypointService.CreateAsync(userId, req.Name, req.Latitude, req.Longitude);
        // Any of the owner's birds with no current nest (a brand-new user's birds, or one
        // who somehow ended up nestless again) get assigned to the nest they just created.
        // This naturally covers "first nest ever" without a special case. Lives here rather
        // than inside WaypointService so Waypoint doesn't take on a dependency on Bird - same
        // composition-at-the-endpoint pattern as GET /friends/waypoints below.
        await birdService.AssignUnassignedBirdsToNestAsync(userId, saved.Id);
        return Results.Created($"/waypoints/{saved.Id}", saved);
    }
    catch (WaypointServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("CreateWaypoint");

app.MapPut("/waypoints/{id}", async (string id, SetWaypointRequest req, ClaimsPrincipal principal, IWaypointService waypointService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        var saved = await waypointService.UpdateAsync(userId, id, req.Name, req.Latitude, req.Longitude);
        return Results.Ok(saved);
    }
    catch (WaypointServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("UpdateWaypoint");

app.MapDelete("/waypoints/{id}", async (string id, ClaimsPrincipal principal, IWaypointService waypointService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await waypointService.DeleteAsync(userId, id);
        return Results.NoContent();
    }
    catch (WaypointServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("DeleteWaypoint");

app.MapGet("/birds", async (ClaimsPrincipal principal, IBirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(await birdService.ListAsync(userId));
})
.RequireAuthorization()
.WithName("ListBirds");

app.MapPost("/friends/requests", async (SendFriendRequestRequest req, ClaimsPrincipal principal, IFriendService friendService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await friendService.SendRequestAsync(userId, req.Username);
        return Results.NoContent();
    }
    catch (FriendServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("SendFriendRequest");

app.MapGet("/friends/requests/incoming", async (ClaimsPrincipal principal, IUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var user = await userRepo.GetByIdAsync(userId);
    if (user is null)
    {
        return Results.Unauthorized();
    }

    var incomingRequests = (user.Friends ?? []).Where(f => f.Status == FriendStatus.PendingIncoming);

    // N+1 lookup to pick up each requester's current ProfilePictureUrl - same accepted
    // tradeoff category as GET /friends, so invite cards can show an avatar.
    var incoming = new List<object>();
    foreach (var request in incomingRequests)
    {
        var requesterUser = await userRepo.GetByIdAsync(request.Id);
        incoming.Add(new { request.Id, request.Username, requesterUser?.ProfilePictureUrl });
    }
    return Results.Ok(incoming);
})
.RequireAuthorization()
.WithName("GetIncomingFriendRequests");

app.MapGet("/friends/requests/outgoing", async (ClaimsPrincipal principal, IUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var user = await userRepo.GetByIdAsync(userId);
    if (user is null)
    {
        return Results.Unauthorized();
    }

    var outgoingRequests = (user.Friends ?? []).Where(f => f.Status == FriendStatus.PendingOutgoing);

    // Same N+1 lookup as incoming requests above, for the same reason.
    var outgoing = new List<object>();
    foreach (var request in outgoingRequests)
    {
        var targetUser = await userRepo.GetByIdAsync(request.Id);
        outgoing.Add(new { request.Id, request.Username, targetUser?.ProfilePictureUrl });
    }
    return Results.Ok(outgoing);
})
.RequireAuthorization()
.WithName("GetOutgoingFriendRequests");

app.MapPost("/friends/requests/{requesterId}/accept", async (string requesterId, ClaimsPrincipal principal, IFriendService friendService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await friendService.AcceptAsync(userId, requesterId);
        return Results.NoContent();
    }
    catch (FriendServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("AcceptFriendRequest");

app.MapDelete("/friends/{userId}", async (string userId, ClaimsPrincipal principal, IFriendService friendService) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    await friendService.RemoveAsync(callerId, userId);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("RemoveFriend");

app.MapGet("/friends", async (ClaimsPrincipal principal, IUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var user = await userRepo.GetByIdAsync(userId);
    if (user is null)
    {
        return Results.Unauthorized();
    }

    var acceptedFriends = (user.Friends ?? []).Where(f => f.Status == FriendStatus.Accepted);

    // N+1 lookup to pick up each friend's current ProfilePictureUrl - same accepted
    // tradeoff category as /friends/waypoints below, fine at expected friend-list sizes.
    var friends = new List<object>();
    foreach (var friend in acceptedFriends)
    {
        var friendUser = await userRepo.GetByIdAsync(friend.Id);
        friends.Add(new { friend.Id, friend.Username, friend.Color, friendUser?.ProfilePictureUrl });
    }

    return Results.Ok(friends);
})
.RequireAuthorization()
.WithName("GetFriends");

app.MapGet("/friends/waypoints", async (ClaimsPrincipal principal, IUserRepository userRepo, IWaypointRepository waypointRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var user = await userRepo.GetByIdAsync(userId);
    if (user is null)
    {
        return Results.Unauthorized();
    }

    var acceptedFriends = (user.Friends ?? []).Where(f => f.Status == FriendStatus.Accepted).ToList();
    var friendIds = acceptedFriends.Select(f => f.Id).ToList();
    var friendWaypoints = await waypointRepo.GetManyByUserIdsAsync(friendIds);

    // One row per friend-nest pair now that a friend can have several nests. The
    // ProfilePictureUrl lookup is cached per friend (not per nest) so a friend with
    // multiple nests doesn't trigger a redundant read of the same user document -
    // same accepted N+1-ish tradeoff as GetByUsernameAsync's cross-partition query,
    // just now N-unique-friends instead of N-nests.
    var results = new List<object>();
    var profileCache = new Dictionary<string, User?>();
    foreach (var waypoint in friendWaypoints)
    {
        var friend = acceptedFriends.First(f => f.Id == waypoint.UserId);
        if (!profileCache.TryGetValue(friend.Id, out var friendUser))
        {
            friendUser = await userRepo.GetByIdAsync(friend.Id);
            profileCache[friend.Id] = friendUser;
        }

        results.Add(new
        {
            waypoint.Id,
            UserId = friend.Id,
            friend.Username,
            friend.Color,
            waypoint.Name,
            waypoint.Latitude,
            waypoint.Longitude,
            friendUser?.ProfilePictureUrl
        });
    }

    return Results.Ok(results);
})
.RequireAuthorization()
.WithName("GetFriendsWaypoints");

app.MapPut("/friends/{userId}/color", async (string userId, SetFriendColorRequest req, ClaimsPrincipal principal, IFriendService friendService) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await friendService.SetColorAsync(callerId, userId, req.Color);
        return Results.NoContent();
    }
    catch (FriendServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("SetFriendColor");

app.MapPut("/profile/picture", async (IFormFile file, ClaimsPrincipal principal, IProfilePictureService pictureService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var url = await pictureService.UploadAsync(userId, stream, file.ContentType, file.Length);
        return Results.Ok(new { ProfilePictureUrl = url });
    }
    catch (ProfilePictureServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("UploadProfilePicture");

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", () =>
{
    var forecast =  Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

record CreateUserRequest(string Username, string Email, string Password);
record LoginRequest(string Username, string Password);
record LoginResponse(string Token, DateTimeOffset ExpiresAt);
record SetWaypointRequest(string Name, double Latitude, double Longitude);
record SendFriendRequestRequest(string Username);
record SetFriendColorRequest(string Color);

public partial class Program { }
