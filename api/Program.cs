using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using CroApp.Api;
using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
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
builder.Services.Configure<BirdTravelOptions>(builder.Configuration.GetSection("BirdTravel"));

builder.Services.AddSingleton(sp =>
{
    var opts = sp.GetRequiredService<IOptions<CosmosDbOptions>>().Value;
    var cosmosClientOptions = new CosmosClientOptions
    {
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    };

    // Two different emulator images are in play (see CLAUDE.md): CI's classic x64 image
    // serves a self-signed HTTPS cert on 8081 and needs this bypass; local Apple Silicon
    // dev's vnext-preview image serves plain HTTP instead, where the callback below simply
    // never fires (no TLS handshake happens over http://) - so setting it unconditionally
    // is correct and harmless for both, rather than branching on which emulator/scheme is
    // in use. Gateway mode is required against either Docker emulator.
    if (opts.UseEmulator)
    {
        cosmosClientOptions.HttpClientFactory = () => new HttpClient(new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        });
        cosmosClientOptions.ConnectionMode = ConnectionMode.Gateway;
    }

    return new CosmosClient(opts.ConnectionString, cosmosClientOptions);
});

builder.Services.AddSingleton(sp =>
{
    var opts = sp.GetRequiredService<IOptions<BlobStorageOptions>>().Value;
    return new BlobServiceClient(opts.ConnectionString);
});

builder.Services.AddScoped<CosmosUserRepository>();
builder.Services.AddScoped<CosmosWaypointRepository>();
builder.Services.AddScoped<WaypointService>();
builder.Services.AddScoped<CosmosBirdRepository>();
builder.Services.AddScoped<BirdService>();
builder.Services.AddScoped<CosmosHubRepository>();
builder.Services.AddScoped<HubService>();
builder.Services.AddScoped<CosmosHubPictureSuggestionRepository>();
builder.Services.AddScoped<HubPictureService>();
builder.Services.AddScoped<CosmosHubMessageRepository>();
builder.Services.AddScoped<CosmosHubReadStateRepository>();
builder.Services.AddScoped<CosmosBirdReadStateRepository>();
builder.Services.AddScoped<CosmosBirdReactionRepository>();
builder.Services.AddScoped<BirdReactionService>();
builder.Services.AddScoped<CosmosEventRepository>();
builder.Services.AddScoped<EventService>();
builder.Services.AddScoped<FriendService>();
builder.Services.AddScoped<PictureUploadService>();
builder.Services.AddScoped<ProfilePictureService>();
builder.Services.AddScoped<NestPictureService>();
builder.Services.AddScoped<BirdPictureService>();
builder.Services.AddScoped<BirdMediaService>();

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
    // Same /userId partition-key reasoning as Waypoints: a user's birds are scoped by
    // owner, keeping "list my birds" and per-bird point ops single-partition.
    await database.Database.CreateContainerIfNotExistsAsync(opts.BirdsContainerName, "/userId");
    // /status, not /userId - a Hub has no single user-owner, and the dominant query is
    // "list every approved Hub" (see Hub.cs), which a /status partition keeps
    // single-partition.
    await database.Database.CreateContainerIfNotExistsAsync(opts.HubsContainerName, "/status");
    // /hubId - the dominant query is "pending photo suggestions for a given hub" plus the
    // admin moderation feed's "every pending suggestion" (a small cross-partition scan),
    // same /hubId reasoning as HubMessages below (see HubPictureSuggestion.cs).
    await database.Database.CreateContainerIfNotExistsAsync(opts.HubPictureSuggestionsContainerName, "/hubId");
    // /birdId, not the reacting user's id - Bird is partitioned by its *sender's* userId,
    // and a reaction from a different user needs its own single-partition read/write path
    // rather than a cross-partition write into the sender's partition (see BirdReaction.cs).
    await database.Database.CreateContainerIfNotExistsAsync(opts.ReactionsContainerName, "/birdId");
    // /hubId, not the poster's userId - dominant query is "list every message posted to a
    // given Hub, newest first", same reasoning as Reactions' /birdId (see HubMessage.cs).
    // DefaultTimeToLive gives every row a native Cosmos TTL of 7 days, auto-expiring the
    // board without a background cleanup job.
    await database.Database.CreateContainerIfNotExistsAsync(
        new ContainerProperties(opts.HubMessagesContainerName, "/hubId") { DefaultTimeToLive = 604800 });
    // /userId, not /hubId - the dominant query is "list every hub-read-state for this user"
    // (used to compute every hub's unread badge in one round trip), same reasoning as
    // Waypoints/Birds above. No TTL - a read state should persist indefinitely, unlike
    // HubMessages' own 7-day board reset.
    await database.Database.CreateContainerIfNotExistsAsync(opts.HubReadStatesContainerName, "/userId");
    // /userId - same reasoning as HubReadStates above, one partition per viewer so "list
    // every public bird I've viewed" (used to badge every friend's public bird on
    // GET /friends/birds) is a single-partition read. No TTL, same "persists indefinitely"
    // choice as HubReadStates.
    await database.Database.CreateContainerIfNotExistsAsync(opts.BirdReadStatesContainerName, "/userId");
    // /userId - the web UI's journey log and notification bell both read "my own history",
    // same single-partition-per-owner reasoning as Waypoints/Birds/HubReadStates above. No
    // TTL, unlike HubMessages' 7-day board reset - this history is the app's one deliberately
    // permanent record, so nothing here ever auto-expires.
    await database.Database.CreateContainerIfNotExistsAsync(opts.EventsContainerName, "/userId");

    if (opts.SeedFixedDevUsersOnStartup)
    {
        // Always-on-launch reset to the same fixed dev dataset Tools/SeedDevUsers seeds
        // manually - wipes Users and reseeds Admin/Test1/Test2/Oliver/Annie (all friends,
        // one Roost nest each, a few Cro's already in flight) every time the API starts.
        await DevDataSeeder.SeedFixedDevUsersAsync(database.Database, opts.UsersContainerName, opts.WaypointsContainerName, opts.BirdsContainerName, opts.HubMessagesContainerName);
    }
    else
    {
        // Dev-only seed users: "Oliver 1" (regular) and "Admin 1" (IsAdmin) so there's always a
        // known admin account locally to place Hubs through the app's own "Add Hub" flow,
        // without a standalone admin-promotion endpoint. Idempotent (checked by username first)
        // so re-running the API against an already-seeded database doesn't error or duplicate.
        // Same well-known-dev-credential category as the Cosmos/Azurite connection strings in
        // CLAUDE.md - never meaningful outside a local emulator.
        var userRepoForSeed = scope.ServiceProvider.GetRequiredService<CosmosUserRepository>();
        var seedHasher = new PasswordHasher<User>();
        async Task SeedDevUserAsync(string username, bool isAdmin)
        {
            if (await userRepoForSeed.GetByUsernameAsync(username) is not null)
            {
                return;
            }
            var seedUser = new User(
                Guid.NewGuid().ToString(),
                username,
                $"{username.Replace(" ", "").ToLowerInvariant()}@example.com",
                DateTimeOffset.UtcNow,
                PasswordHash: "",
                Friends: [],
                IsAdmin: isAdmin);
            seedUser = seedUser with { PasswordHash = seedHasher.HashPassword(seedUser, "correct-horse-battery-staple") };
            await userRepoForSeed.CreateAsync(seedUser);
        }
        await SeedDevUserAsync("Oliver 1", isAdmin: false);
        await SeedDevUserAsync("Admin 1", isAdmin: true);
    }

    var blobClient = scope.ServiceProvider.GetRequiredService<BlobServiceClient>();
    var blobOpts = scope.ServiceProvider.GetRequiredService<IOptions<BlobStorageOptions>>().Value;
    // PublicAccessType.Blob (public read for blobs, no container listing) keeps uploaded
    // pictures fetchable via a plain URL without SAS tokens - fine for local/dev, but a
    // real deployment needs real access control here before this container goes live.
    await blobClient.GetBlobContainerClient(blobOpts.ProfilePicturesContainerName)
        .CreateIfNotExistsAsync(PublicAccessType.Blob);
    // Same public-read, dev-only tradeoff as profile-pictures above - a nest's picture is
    // shown to any friend who can already see that nest via /friends/waypoints.
    await blobClient.GetBlobContainerClient(blobOpts.NestPicturesContainerName)
        .CreateIfNotExistsAsync(PublicAccessType.Blob);
    // Same tradeoff again - a Hub's picture, shared by both pending suggestions (previewed
    // in the admin moderation feed) and the approved picture itself.
    await blobClient.GetBlobContainerClient(blobOpts.HubPicturesContainerName)
        .CreateIfNotExistsAsync(PublicAccessType.Blob);
    // Same tradeoff again - a bird's own avatar.
    await blobClient.GetBlobContainerClient(blobOpts.BirdPicturesContainerName)
        .CreateIfNotExistsAsync(PublicAccessType.Blob);
    // A composed bird's payload media (Parrot audio, Pigeon/Raven image) - separate
    // container from the avatar above so the two never collide.
    await blobClient.GetBlobContainerClient(blobOpts.BirdMediaContainerName)
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

app.MapPost("/users", async (CreateUserRequest req, CosmosUserRepository repo) =>
{
    var hasher = new PasswordHasher<User>();
    var user = new User(Guid.NewGuid().ToString(), req.Username, req.Email, DateTimeOffset.UtcNow, PasswordHash: "", Friends: []);
    var hashedUser = user with { PasswordHash = hasher.HashPassword(user, req.Password) };
    var created = await repo.CreateAsync(hashedUser);
    return Results.Created($"/users/{created.Id}", created.ToResponse());
})
.WithName("CreateUser");

app.MapGet("/users/{id}", async (string id, CosmosUserRepository repo) =>
    await repo.GetByIdAsync(id) is { } user ? Results.Ok(user.ToResponse()) : Results.NotFound())
.WithName("GetUserById");

// Grant-only (no revoke endpoint - not needed yet). Same inline caller-lookup-then-IsAdmin
// gate as POST /hubs, checked per-request rather than via a JWT claim so a freshly-granted
// admin doesn't need to re-log-in for it to take effect.
app.MapPost("/users/{id}/make-admin", async (string id, ClaimsPrincipal principal, CosmosUserRepository userRepo) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(callerId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    var target = await userRepo.GetByIdAsync(id);
    if (target is null)
    {
        return Results.NotFound();
    }

    var updated = await userRepo.UpdateAsync(target with { IsAdmin = true });
    return Results.Ok(updated.ToResponse());
})
.RequireAuthorization()
.WithName("MakeUserAdmin");

// Powers the Profile screen's live "Add Friends" suggestions as the caller types - unlike
// GET /users/{id}, this is authenticated (it's a directory search over every user, not a
// single already-known id) and deliberately returns only id/username/profilePictureUrl,
// the same minimal shape as the friend-request endpoints below, never email or the friends
// graph. The caller's own account is excluded so the search box can never suggest
// friending yourself. Route ordering vs. GET /users/{id} above doesn't matter - ASP.NET
// Core's endpoint routing prefers the literal "search" segment over the {id} parameter
// regardless of registration order.
app.MapGet("/users/search", async (string? q, ClaimsPrincipal principal, CosmosUserRepository repo) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    var prefix = q?.Trim() ?? "";
    if (prefix.Length == 0)
    {
        return Results.Ok(Array.Empty<object>());
    }

    var matches = await repo.SearchByUsernamePrefixAsync(prefix, limit: 8);
    var results = matches
        .Where(u => u.Id != callerId)
        .Select(u => new { u.Id, u.Username, u.ProfilePictureUrl });
    return Results.Ok(results);
})
.RequireAuthorization()
.WithName("SearchUsers");

app.MapPost("/login", async (LoginRequest req, CosmosUserRepository repo, IOptions<JwtOptions> jwtOpts) =>
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

app.MapGet("/waypoints", async (ClaimsPrincipal principal, WaypointService waypointService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var waypoints = await waypointService.ListAsync(userId);
    // A nest without its own picture falls back to its owner's profile picture - resolved
    // here (not stored on the Waypoint document) so re-uploading a profile picture is
    // instantly reflected on every nest that hasn't set its own, same fallback GET
    // /friends/waypoints applies below.
    var user = await userRepo.GetByIdAsync(userId);
    var resolved = waypoints
        .Select(w => w with { ProfilePictureUrl = w.ProfilePictureUrl ?? user?.ProfilePictureUrl })
        .ToList();
    return Results.Ok(resolved);
})
.RequireAuthorization()
.WithName("ListWaypoints");

app.MapPost("/waypoints", async (SetWaypointRequest req, ClaimsPrincipal principal, WaypointService waypointService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        var saved = await waypointService.CreateAsync(userId, req.Name, req.Latitude, req.Longitude, req.IsPublic);
        return Results.Created($"/waypoints/{saved.Id}", saved);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("CreateWaypoint");

app.MapPut("/waypoints/{id}", async (string id, SetWaypointRequest req, ClaimsPrincipal principal, WaypointService waypointService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("UpdateWaypoint");

app.MapDelete("/waypoints/{id}", async (string id, ClaimsPrincipal principal, WaypointService waypointService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("DeleteWaypoint");

app.MapGet("/hubs", async (ClaimsPrincipal principal, HubService hubService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(await hubService.ListApprovedAsync());
})
.RequireAuthorization()
.WithName("ListHubs");

app.MapPost("/hubs", async (SetHubRequest req, ClaimsPrincipal principal, HubService hubService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    // Admin check is a per-request repository lookup rather than a JWT claim, so granting
    // or revoking IsAdmin takes effect immediately without re-issuing tokens - see User.cs.
    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    if (!HubCategoryCatalog.IsValid(req.Category))
    {
        return Results.Json(new { error = $"Unknown category '{req.Category}'." }, statusCode: 400);
    }

    var saved = await hubService.CreateAsync(userId, req.Name, req.Latitude, req.Longitude, req.Category);
    return Results.Created($"/hubs/{saved.Id}", saved);
})
.RequireAuthorization()
.WithName("CreateHub");

// Any authenticated user can suggest a Hub location - unlike POST /hubs, there's no admin
// gate here. The suggestion lands in the Pending partition and never appears on GET /hubs
// (which only ever lists Approved) until an admin approves it below.
app.MapPost("/hub-suggestions", async (SetHubRequest req, ClaimsPrincipal principal, HubService hubService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    if (!HubCategoryCatalog.IsValid(req.Category))
    {
        return Results.Json(new { error = $"Unknown category '{req.Category}'." }, statusCode: 400);
    }

    var saved = await hubService.SuggestAsync(userId, req.Name, req.Latitude, req.Longitude, req.Category);
    return Results.Created($"/hub-suggestions/{saved.Id}", saved);
})
.RequireAuthorization()
.WithName("SuggestHub");

// The admin moderation feed - same caller-lookup-then-IsAdmin gate as POST /hubs.
app.MapGet("/hub-suggestions", async (ClaimsPrincipal principal, HubService hubService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    return Results.Ok(await hubService.ListPendingAsync());
})
.RequireAuthorization()
.WithName("ListHubSuggestions");

app.MapPost("/hub-suggestions/{id}/approve", async (string id, ClaimsPrincipal principal, HubService hubService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    try
    {
        var approved = await hubService.ApproveAsync(id);
        return Results.Ok(approved);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("ApproveHubSuggestion");

app.MapDelete("/hub-suggestions/{id}", async (string id, ClaimsPrincipal principal, HubService hubService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    try
    {
        await hubService.RejectAsync(id);
        return Results.NoContent();
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("RejectHubSuggestion");

// Any authenticated user can suggest a photo for an existing (Approved) Hub - unlike a
// Hub location suggestion, this doesn't create a new Hub, just a Pending picture attached
// to one that already exists. Same admin-approval gate as hub-suggestions above, so a
// shared/ownerless Hub's picture can't be griefed by an unmoderated upload.
app.MapPost("/hubs/{id}/picture-suggestions", async (string id, IFormFile file, ClaimsPrincipal principal, HubPictureService hubPictureService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var suggestion = await hubPictureService.SuggestAsync(id, userId, stream, file.ContentType, file.Length);
        return Results.Created($"/hub-picture-suggestions/{suggestion.Id}", suggestion);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("SuggestHubPicture");

// The admin moderation feed - same caller-lookup-then-IsAdmin gate as GET /hub-suggestions.
app.MapGet("/hub-picture-suggestions", async (ClaimsPrincipal principal, HubPictureService hubPictureService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    return Results.Ok(await hubPictureService.ListPendingAsync());
})
.RequireAuthorization()
.WithName("ListHubPictureSuggestions");

app.MapPost("/hub-picture-suggestions/{id}/approve", async (string id, ClaimsPrincipal principal, HubPictureService hubPictureService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    try
    {
        var hub = await hubPictureService.ApproveAsync(id);
        return Results.Ok(hub);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("ApproveHubPictureSuggestion");

app.MapDelete("/hub-picture-suggestions/{id}", async (string id, ClaimsPrincipal principal, HubPictureService hubPictureService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var caller = await userRepo.GetByIdAsync(userId);
    if (caller is null || !caller.IsAdmin)
    {
        return Results.Forbid();
    }

    try
    {
        await hubPictureService.RejectAsync(id);
        return Results.NoContent();
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("RejectHubPictureSuggestion");

app.MapGet("/hubs/{id}/birds", async (string id, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        var residents = await birdService.GetHubResidentsAsync(id);
        // Mask payload behind IsPublic, same rule GET /friends/birds already applies - a
        // Hub-bound bird can be non-public now (see BirdService.ComposeAndSendAsync), so
        // this live "who's here" view hides its content for everyone until it's public.
        var results = residents.Select(bird => new
        {
            bird.Id,
            bird.UserId,
            bird.Name,
            bird.Type,
            bird.CurrentNestId,
            bird.IsPublic,
            Content = bird.IsPublic ? bird.Content : null,
            AudioUrl = bird.IsPublic ? bird.AudioUrl : null,
            ImageUrl = bird.IsPublic ? bird.ImageUrl : null,
        });
        return Results.Ok(results);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("GetHubResidentBirds");

// The Hub message board - durable history of everything that's ever landed at this Hub,
// independent of GetHubResidentBirds' live "who's currently here" snapshot (see
// HubMessage.cs). Deliberately not masked by IsPublic the way GetHubResidentBirds is
// above - a Hub-bound bird can be non-public, but the board is a public log of everything
// that's ever arrived here regardless, so every row shows in full.
app.MapGet("/hubs/{id}/messages", async (string id, ClaimsPrincipal principal, CosmosHubMessageRepository hubMessageRepository, CosmosHubRepository hubRepository, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    if (await hubRepository.GetAsync(id) is null)
    {
        return Results.Json(new { error = "Hub not found." }, statusCode: 404);
    }

    var messages = await hubMessageRepository.ListByHubIdAsync(id);

    // N+1 lookup for each sender's current ProfilePictureUrl - same accepted tradeoff as
    // GET /friends and friends, deliberately not snapshotted onto HubMessage (see its
    // comment) so an avatar update stays current even on old board posts.
    var results = new List<object>();
    foreach (var message in messages)
    {
        var sender = await userRepo.GetByIdAsync(message.SenderId);
        results.Add(new
        {
            message.Id,
            message.SenderId,
            message.SenderUsername,
            message.BirdName,
            message.OriginNestName,
            message.Type,
            message.Content,
            message.AudioUrl,
            message.ImageUrl,
            message.CreatedAt,
            SenderProfilePictureUrl = sender?.ProfilePictureUrl,
        });
    }
    return Results.Ok(results);
})
.RequireAuthorization()
.WithName("GetHubMessages");

// Powers the unread-count badge under each Hub marker on the map. Same accepted N+1-per-Hub
// tradeoff category as GET /friends/waypoints ("fine at expected sizes") - fetches every
// approved Hub's full message list to count how many postdate the caller's last-read
// timestamp for that hub (MinValue, i.e. "everything," if they've never opened it).
app.MapGet("/hubs/unread-counts", async (ClaimsPrincipal principal, CosmosHubRepository hubRepository, CosmosHubMessageRepository hubMessageRepository, CosmosHubReadStateRepository readStateRepository) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var hubs = await hubRepository.ListApprovedAsync();
    var readStates = (await readStateRepository.ListForUserAsync(userId))
        .ToDictionary(r => r.HubId, r => r.LastReadAt);

    var counts = new Dictionary<string, int>();
    foreach (var hub in hubs)
    {
        var lastReadAt = readStates.TryGetValue(hub.Id, out var readAt) ? readAt : DateTimeOffset.MinValue;
        var messages = await hubMessageRepository.ListByHubIdAsync(hub.Id);
        counts[hub.Id] = messages.Count(m => m.CreatedAt > lastReadAt);
    }
    return Results.Ok(counts);
})
.RequireAuthorization()
.WithName("GetHubUnreadCounts");

app.MapPost("/hubs/{id}/read", async (string id, ClaimsPrincipal principal, CosmosHubRepository hubRepository, CosmosHubReadStateRepository readStateRepository) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    if (await hubRepository.GetAsync(id) is null)
    {
        return Results.Json(new { error = "Hub not found." }, statusCode: 404);
    }

    await readStateRepository.MarkReadAsync(userId, id, DateTimeOffset.UtcNow);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("MarkHubRead");

app.MapGet("/birds", async (ClaimsPrincipal principal, BirdService birdService) =>
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

app.MapPost("/birds/compose", async (
    [FromForm] string type,
    [FromForm] string name,
    [FromForm] string originNestId,
    [FromForm] string destinationId,
    [FromForm] string? content,
    IFormFile? file,
    ClaimsPrincipal principal,
    BirdService birdService,
    [FromForm] bool isPublic = false) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var mediaStream = file?.OpenReadStream();
    try
    {
        var created = await birdService.ComposeAndSendAsync(
            userId, type, name, originNestId, destinationId, content, isPublic,
            mediaStream, file?.ContentType, file?.Length ?? 0);
        return Results.Created($"/birds/{created.Id}", created);
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
    finally
    {
        if (mediaStream is not null)
        {
            await mediaStream.DisposeAsync();
        }
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("ComposeBird");

app.MapPut("/birds/{id}", async (string id, RenameBirdRequest req, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        return Results.Ok(await birdService.RenameAsync(userId, id, req.Name));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("RenameBird");

app.MapDelete("/birds/{id}", async (string id, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await birdService.DeleteAsync(userId, id);
        return Results.NoContent();
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("DeleteBird");

app.MapPut("/birds/{id}/picture", async (string id, IFormFile file, ClaimsPrincipal principal, BirdPictureService pictureService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var url = await pictureService.UploadAsync(userId, id, stream, file.ContentType, file.Length);
        return Results.Ok(new { ProfilePictureUrl = url });
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("UploadBirdPicture");

app.MapPost("/birds/{id}/send", async (string id, SendBirdRequest req, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        return Results.Ok(await birdService.SendAsync(userId, id, req.NestId, req.Content));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("SendBird");

app.MapGet("/waypoints/{id}/birds", async (string id, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        return Results.Ok(await birdService.GetNestResidentsAsync(userId, id));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("GetNestResidentBirds");

app.MapPost("/birds/{id}/read", async (string id, ClaimsPrincipal principal, BirdService birdService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        return Results.Ok(await birdService.MarkReadAsync(userId, id));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("MarkBirdRead");

// Distinct from POST /birds/{id}/read above: that one is the *owner* marking their own
// delivered bird read (gated on currently sitting in a nest they own). This is any friend
// marking a public bird - theirs or someone else's - as viewed, the same "differs per
// viewer, not per owner" reasoning BirdReadState.cs documents. Only public birds can be
// viewed this way; a private bird has nothing for a friend to see yet.
app.MapPost("/birds/{id}/viewed", async (string id, ClaimsPrincipal principal, CosmosBirdRepository birdRepository, CosmosBirdReadStateRepository readStateRepository) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var bird = await birdRepository.GetByIdAsync(id);
    if (bird is null)
    {
        return Results.Json(new { error = "Bird not found." }, statusCode: 404);
    }
    if (!bird.IsPublic)
    {
        return Results.Json(new { error = "Only public birds can be marked viewed." }, statusCode: 400);
    }

    await readStateRepository.MarkReadAsync(userId, id, DateTimeOffset.UtcNow);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("MarkBirdViewed");

app.MapGet("/birds/{id}/reactions", async (string id, ClaimsPrincipal principal, BirdReactionService reactionService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        return Results.Ok(await reactionService.GetSummaryAsync(userId, id));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("GetBirdReactions");

app.MapPut("/birds/{id}/reactions/{emoji}", async (string id, string emoji, ClaimsPrincipal principal, BirdReactionService reactionService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await reactionService.AddAsync(userId, id, emoji);
        return Results.Ok(await reactionService.GetSummaryAsync(userId, id));
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("AddBirdReaction");

app.MapDelete("/birds/{id}/reactions/{emoji}", async (string id, string emoji, ClaimsPrincipal principal, BirdReactionService reactionService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    await reactionService.RemoveAsync(userId, id, emoji);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("RemoveBirdReaction");

app.MapPost("/friends/requests", async (SendFriendRequestRequest req, ClaimsPrincipal principal, FriendService friendService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("SendFriendRequest");

app.MapGet("/friends/requests/incoming", async (ClaimsPrincipal principal, CosmosUserRepository userRepo) =>
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

app.MapGet("/friends/requests/outgoing", async (ClaimsPrincipal principal, CosmosUserRepository userRepo) =>
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

app.MapPost("/friends/requests/{requesterId}/accept", async (string requesterId, ClaimsPrincipal principal, FriendService friendService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("AcceptFriendRequest");

app.MapPost("/friends/requests/{requesterId}/decline", async (string requesterId, ClaimsPrincipal principal, FriendService friendService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    await friendService.DeclineAsync(userId, requesterId);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("DeclineFriendRequest");

app.MapDelete("/friends/{userId}", async (string userId, ClaimsPrincipal principal, FriendService friendService) =>
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

app.MapPost("/friends/{userId}/block", async (string userId, ClaimsPrincipal principal, FriendService friendService) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await friendService.BlockAsync(callerId, userId);
        return Results.NoContent();
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("BlockUser");

app.MapDelete("/friends/{userId}/block", async (string userId, ClaimsPrincipal principal, FriendService friendService) =>
{
    var callerId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (callerId is null)
    {
        return Results.Unauthorized();
    }

    await friendService.UnblockAsync(callerId, userId);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("UnblockUser");

app.MapGet("/friends/blocked", async (ClaimsPrincipal principal, FriendService friendService, CosmosUserRepository userRepo) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var blockedIds = await friendService.ListBlockedAsync(userId);

    // Same N+1 username/avatar lookup pattern as GET /friends - fine at expected
    // blocked-list sizes.
    var blocked = new List<object>();
    foreach (var blockedId in blockedIds)
    {
        var blockedUser = await userRepo.GetByIdAsync(blockedId);
        if (blockedUser is not null)
        {
            blocked.Add(new { blockedUser.Id, blockedUser.Username, blockedUser.ProfilePictureUrl });
        }
    }
    return Results.Ok(blocked);
})
.RequireAuthorization()
.WithName("GetBlockedUsers");

app.MapGet("/friends", async (ClaimsPrincipal principal, CosmosUserRepository userRepo) =>
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
        friends.Add(new { friend.Id, friend.Username, friend.Color, friendUser?.ProfilePictureUrl, IsAdmin = friendUser?.IsAdmin ?? false });
    }

    return Results.Ok(friends);
})
.RequireAuthorization()
.WithName("GetFriends");

app.MapGet("/friends/waypoints", async (ClaimsPrincipal principal, CosmosUserRepository userRepo, CosmosWaypointRepository waypointRepo) =>
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
            ProfilePictureUrl = waypoint.ProfilePictureUrl ?? friendUser?.ProfilePictureUrl
        });
    }

    return Results.Ok(results);
})
.RequireAuthorization()
.WithName("GetFriendsWaypoints");

app.MapGet("/friends/birds", async (ClaimsPrincipal principal, CosmosUserRepository userRepo, BirdService birdService, CosmosBirdReadStateRepository readStateRepository) =>
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

    // The caller's own view history for public birds - used below to badge each returned
    // public bird as viewed/unviewed, same one-round-trip-per-request shape as
    // GET /hubs/unread-counts.
    var viewedBirdIds = (await readStateRepository.ListForUserAsync(userId))
        .Select(r => r.BirdId)
        .ToHashSet();

    // Every flight path/bird on the map is colored by whoever sent it, not by
    // destination, so the caller's own nest can show several different friends'
    // colors converging on it - each friend's Color here is that friend's own
    // assigned color, same field GetFriendsWaypoints uses for their nest pins.
    var friendsById = acceptedFriends.ToDictionary(f => f.Id);
    var travelingBirds = await birdService.ListTravelingForUsersAsync(friendsById.Keys);
    var results = travelingBirds.Select(bird =>
    {
        var friend = friendsById[bird.UserId];
        return new
        {
            bird.Id,
            UserId = friend.Id,
            friend.Username,
            friend.Color,
            bird.Name,
            bird.Type,
            bird.NestFromId,
            bird.NestToId,
            bird.DepartedAt,
            bird.EstimatedArrivalAt,
            bird.IsPublic,
            // A friend's still-in-flight private bird's message stays a surprise until it
            // lands at the caller's own nest - only a public bird's payload is fair game
            // to show here, same "IsPublic gates it" rule reactions already follow.
            Content = bird.IsPublic ? bird.Content : null,
            AudioUrl = bird.IsPublic ? bird.AudioUrl : null,
            ImageUrl = bird.IsPublic ? bird.ImageUrl : null,
            // Only meaningful for a public bird (see POST /birds/{id}/viewed) - always
            // false for a private one, since there's nothing to have viewed yet.
            HasViewed = bird.IsPublic && viewedBirdIds.Contains(bird.Id),
        };
    }).ToList();

    return Results.Ok(results);
})
.RequireAuthorization()
.WithName("GetFriendsBirds");

app.MapPut("/friends/{userId}/color", async (string userId, SetFriendColorRequest req, ClaimsPrincipal principal, FriendService friendService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("SetFriendColor");

app.MapPut("/profile/picture", async (IFormFile file, ClaimsPrincipal principal, ProfilePictureService pictureService) =>
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
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("UploadProfilePicture");

app.MapPut("/waypoints/{id}/picture", async (string id, IFormFile file, ClaimsPrincipal principal, NestPictureService pictureService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var url = await pictureService.UploadAsync(userId, id, stream, file.ContentType, file.Length);
        return Results.Ok(new { ProfilePictureUrl = url });
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.DisableAntiforgery()
.WithName("UploadNestPicture");

// The web UI's "journey log" - every event ever recorded for the caller, newest first,
// never pruned (see Event.cs/EventService). No projection needed: Event.UserId is always
// the caller's own, there's nothing here to hide from them.
app.MapGet("/events", async (int? limit, ClaimsPrincipal principal, EventService eventService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(await eventService.ListTimelineAsync(userId, limit ?? 200));
})
.RequireAuthorization()
.WithName("ListEvents");

// The notification bell's dropdown - the IsNotification subset of the same event history.
app.MapGet("/notifications", async (int? limit, ClaimsPrincipal principal, EventService eventService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(await eventService.ListNotificationsAsync(userId, limit ?? 50));
})
.RequireAuthorization()
.WithName("ListNotifications");

app.MapGet("/notifications/unread-count", async (ClaimsPrincipal principal, EventService eventService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(new { Count = await eventService.CountUnreadNotificationsAsync(userId) });
})
.RequireAuthorization()
.WithName("GetUnreadNotificationCount");

app.MapPost("/notifications/{id}/read", async (string id, ClaimsPrincipal principal, EventService eventService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    try
    {
        await eventService.MarkNotificationReadAsync(userId, id);
        return Results.NoContent();
    }
    catch (ServiceException ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: ex.StatusCode);
    }
})
.RequireAuthorization()
.WithName("MarkNotificationRead");

app.MapPost("/notifications/read-all", async (ClaimsPrincipal principal, EventService eventService) =>
{
    var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    if (userId is null)
    {
        return Results.Unauthorized();
    }

    await eventService.MarkAllNotificationsReadAsync(userId);
    return Results.NoContent();
})
.RequireAuthorization()
.WithName("MarkAllNotificationsRead");

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
// IsPublic is only honored by CreateWaypoint - UpdateWaypoint reuses this same DTO but
// ignores the field entirely, since a nest's kind is not editable after creation.
record SetWaypointRequest(string Name, double Latitude, double Longitude, bool IsPublic = false);
record SetHubRequest(string Name, double Latitude, double Longitude, string Category);
record SendBirdRequest(string NestId, string? Content);
record RenameBirdRequest(string Name);
record SendFriendRequestRequest(string Username);
record SetFriendColorRequest(string Color);

public partial class Program { }
