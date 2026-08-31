using CroApp.Api;
using Microsoft.Azure.Cosmos;

// Thin CLI wrapper around DevDataSeeder.SeedFixedDevUsersAsync (the shared implementation
// CroApp.Api's own dev-only startup also calls on every `dotnet run` - see Program.cs) so
// this can still be run standalone against a running emulator without starting the API.
//
// Talks directly to the Cosmos emulator (same TLS-bypass/Gateway-mode setup Program.cs
// uses) rather than through the running API, so it works whether or not `dotnet run` is
// up, and so the container wipe (no DELETE /users endpoint exists) is possible at all.

const string DatabaseName = "CroApp";
const string UsersContainerName = "Users";
const string WaypointsContainerName = "Waypoints";
const string BirdsContainerName = "Birds";

// Same well-known, publicly-documented emulator key as CLAUDE.md's setup instructions -
// identical on every local install, never meaningful outside a local emulator. Overridable
// via COSMOS_CONNECTION_STRING for anyone running against a differently-configured emulator.
// http://, not https:// - this repo's local dev target is the ARM64 vnext-preview image
// (see CLAUDE.md), which serves a plain-HTTP gateway rather than the classic emulator's
// self-signed HTTPS cert.
const string DefaultEmulatorConnectionString =
    "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";

var connectionString = Environment.GetEnvironmentVariable("COSMOS_CONNECTION_STRING") ?? DefaultEmulatorConnectionString;

var cosmosClientOptions = new CosmosClientOptions
{
    SerializerOptions = new CosmosSerializationOptions
    {
        PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
    },
    ConnectionMode = ConnectionMode.Gateway,
    HttpClientFactory = () => new HttpClient(new HttpClientHandler
    {
        ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
    })
};

using var client = new CosmosClient(connectionString, cosmosClientOptions);
var database = client.GetDatabase(DatabaseName);

await DevDataSeeder.SeedFixedDevUsersAsync(database, UsersContainerName, WaypointsContainerName, BirdsContainerName);
