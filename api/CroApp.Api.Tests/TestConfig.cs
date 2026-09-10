namespace CroApp.Api.Tests;

// Shared in-memory config for every WebApplicationFactory<Program> fixture in this project.
// Program.cs's dev-only startup provisioning (container/blob-container creation) reads every
// CosmosDb/BlobStorage key unconditionally and throws if one resolves to its C# default
// (empty string), so a fixture that only lists the keys its own test touches fails to boot
// at all - see TECH_DEBT.md's "fixture config gap" entry. Build() always returns the full
// key set; pass connection-string overrides only when a test needs something other than the
// local emulator/Azurite defaults.
internal static class TestConfig
{
    private const string DefaultEmulatorConnectionString =
        "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
    private const string DefaultAzuriteConnectionString = "UseDevelopmentStorage=true";

    internal static string ResolveCosmosConnectionString() =>
        Environment.GetEnvironmentVariable("CosmosDb__ConnectionString") ?? DefaultEmulatorConnectionString;

    internal static string ResolveBlobConnectionString() =>
        Environment.GetEnvironmentVariable("BlobStorage__ConnectionString") ?? DefaultAzuriteConnectionString;

    internal static Dictionary<string, string?> Build(string? cosmosConnectionString = null, string? blobConnectionString = null) => new()
    {
        ["CosmosDb:UseEmulator"] = "true",
        ["CosmosDb:ConnectionString"] = cosmosConnectionString ?? ResolveCosmosConnectionString(),
        ["CosmosDb:DatabaseName"] = "CroApp",
        ["CosmosDb:UsersContainerName"] = "Users",
        ["CosmosDb:WaypointsContainerName"] = "Waypoints",
        ["CosmosDb:BirdsContainerName"] = "Birds",
        ["CosmosDb:HubsContainerName"] = "Hubs",
        ["CosmosDb:HubPictureSuggestionsContainerName"] = "HubPictureSuggestions",
        ["CosmosDb:ReactionsContainerName"] = "Reactions",
        ["CosmosDb:HubMessagesContainerName"] = "HubMessages",
        ["CosmosDb:HubReadStatesContainerName"] = "HubReadStates",
        ["CosmosDb:BirdReadStatesContainerName"] = "BirdReadStates",
        ["CosmosDb:EventsContainerName"] = "Events",
        ["BlobStorage:ConnectionString"] = blobConnectionString ?? ResolveBlobConnectionString(),
        ["BlobStorage:ProfilePicturesContainerName"] = "profile-pictures",
        ["BlobStorage:NestPicturesContainerName"] = "nest-pictures",
        ["BlobStorage:HubPicturesContainerName"] = "hub-pictures",
        ["BlobStorage:BirdPicturesContainerName"] = "bird-pictures",
        ["BlobStorage:BirdMediaContainerName"] = "bird-media",
        ["Jwt:SigningKey"] = UsersEndpointTests.TestJwtSigningKey,
        ["Jwt:Issuer"] = "CroApp.Api.Tests",
        ["Jwt:Audience"] = "CroApp.Api.Tests"
    };
}
