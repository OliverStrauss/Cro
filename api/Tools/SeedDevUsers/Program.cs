using CroApp.Api.Models;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.Azure.Cosmos;
using User = CroApp.Api.Models.User;

// Resets the Users container to a fixed, known-good set of dev accounts, all already
// friends with each other. Only the Users container is touched - Hubs, Waypoints, Birds,
// and Reactions are left exactly as they are, so locally-placed Hubs survive a re-run.
//
// Talks directly to the Cosmos emulator (same TLS-bypass/Gateway-mode setup Program.cs
// uses) rather than through the running API, so it works whether or not `dotnet run` is
// up, and so the container wipe (no DELETE /users endpoint exists) is possible at all.

const string DatabaseName = "CroApp";
const string UsersContainerName = "Users";
const string Password = "1";

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
var usersContainer = client.GetDatabase(DatabaseName).GetContainer(UsersContainerName);

Console.WriteLine("Wiping existing Users (Hubs, Waypoints, Birds, and Reactions are untouched)...");
var existingIds = new List<string>();
var query = usersContainer.GetItemQueryIterator<User>(new QueryDefinition("SELECT * FROM c"));
while (query.HasMoreResults)
{
    foreach (var existing in await query.ReadNextAsync())
    {
        existingIds.Add(existing.Id);
    }
}
foreach (var id in existingIds)
{
    // Partition key is /id, same as CosmosUserRepository.
    await usersContainer.DeleteItemAsync<User>(id, new PartitionKey(id));
}
Console.WriteLine($"Deleted {existingIds.Count} existing user(s).");

string[] usernames = ["Admin", "Test1", "Test2", "Oliver", "Annie"];
var hasher = new PasswordHasher<User>();

var users = usernames.ToDictionary(username => username, username =>
{
    var user = new User(
        Guid.NewGuid().ToString(),
        username,
        $"{username.ToLowerInvariant()}@example.com",
        DateTimeOffset.UtcNow,
        PasswordHash: "",
        Friends: [],
        // "Admin" gets the same IsAdmin: true treatment Program.cs's own dev seed gives
        // "Admin 1", so it can place Hubs via the map's "Add Hub" button.
        IsAdmin: username == "Admin");
    return user with { PasswordHash = hasher.HashPassword(user, Password) };
});

// Every user Accepted-friends every other user. Each side's Color is picked independently
// via the same FriendColorPalette.PickNext logic FriendService.AcceptAsync uses, in
// username order, so the graph looks exactly like it would if these had been accepted one
// at a time through the app.
foreach (var username in usernames)
{
    var user = users[username];
    var friendEntries = new List<FriendEntry>();
    foreach (var otherUsername in usernames.Where(u => u != username))
    {
        var other = users[otherUsername];
        var color = FriendColorPalette.PickNext(friendEntries.Select(f => f.Color!));
        friendEntries.Add(new FriendEntry(other.Id, other.Username, FriendStatus.Accepted, color));
    }
    users[username] = user with { Friends = friendEntries };
}

foreach (var username in usernames)
{
    var user = users[username];
    await usersContainer.CreateItemAsync(user, new PartitionKey(user.Id));
    Console.WriteLine($"Created {username} (password: {Password}, id: {user.Id})");
}

Console.WriteLine("Done - all 5 users are friends with each other.");
