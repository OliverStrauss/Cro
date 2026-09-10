using CroApp.Api.Models;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.Azure.Cosmos;
using User = CroApp.Api.Models.User;

namespace CroApp.Api;

// Shared body of what used to be Tools/SeedDevUsers' own Program.cs, extracted so both the
// standalone tool (manual `dotnet run` against a running emulator) and CroApp.Api's own
// dev-only startup (see Program.cs) reset to the exact same known-good dev dataset, without
// the two drifting apart. Resets the Users container to a fixed, known-good set of dev
// accounts, all already friends with each other, each with one private, uniquely-named
// "{Username}'s Roost" nest around Ames, a full 5-bird starter roster (see
// BirdTypeCatalog.StarterRoster) sitting home at that Roost, plus a few extra seed Birds sent
// between them for demo variety. Users is
// wiped and replaced; Waypoints and Birds only ever get new rows added, never wiped (so
// locally-placed Hubs and any manually-sent birds survive a re-run) - Hubs themselves and
// Reactions are left exactly as they are. HubMessages IS wiped, unlike those: it's the one
// other container that stores a snapshotted Users reference (SenderId) rather than owning
// its own identity, so leaving old rows in place after a Users wipe wouldn't just be inert
// leftover data - the web UI's Hub message board reads that stale SenderId to decide
// whether to show an "Add friend" button, and a since-deleted sender's id can no longer
// match anyone in the new users' friend lists, wrongly showing that button for someone
// who's actually already a friend under their new id.
public static class DevDataSeeder
{
    private const string Password = "1";

    public static async Task SeedFixedDevUsersAsync(Database database, string usersContainerName, string waypointsContainerName, string birdsContainerName, string hubMessagesContainerName)
    {
        var usersContainer = database.GetContainer(usersContainerName);
        var waypointsContainer = database.GetContainer(waypointsContainerName);
        var birdsContainer = database.GetContainer(birdsContainerName);
        var hubMessagesContainer = database.GetContainer(hubMessagesContainerName);

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

        // Every existing HubMessage.SenderId now points at a user just deleted above, so the
        // whole board is stale, not just seeded users' own rows - wipe it all rather than try
        // to pick out which ones still resolve. Cross-partition (partitioned by HubId, not
        // SenderId), so a plain SELECT here has no single partition key to scope to.
        var hubMessageIds = new List<(string Id, string HubId)>();
        var hubMessageQuery = hubMessagesContainer.GetItemQueryIterator<HubMessage>(new QueryDefinition("SELECT * FROM c"));
        while (hubMessageQuery.HasMoreResults)
        {
            foreach (var existing in await hubMessageQuery.ReadNextAsync())
            {
                hubMessageIds.Add((existing.Id, existing.HubId));
            }
        }
        foreach (var (id, hubId) in hubMessageIds)
        {
            await hubMessagesContainer.DeleteItemAsync<HubMessage>(id, new PartitionKey(hubId));
        }
        Console.WriteLine($"Cleared {hubMessageIds.Count} Hub message board row(s) (stale sender references after the Users wipe above).");

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

        // One private, uniquely-named nest per user, spread across real Ames landmarks so they
        // don't all stack on the same map pin. Coordinates match the map's Ames-scoped default view.
        // A user can have at most one nest (see WaypointService.CreateAsync) - this is that slot.
        (string Username, double Latitude, double Longitude)[] homeBases =
        [
            ("Admin", 42.0305, -93.6188),  // Ames City Hall
            ("Test1", 42.0181, -93.6423),  // Reiman Gardens
            ("Test2", 42.0141, -93.6358),  // Jack Trice Stadium
            ("Oliver", 42.0266, -93.6465), // Iowa State Campanile
            ("Annie", 42.0572, -93.6404),  // Ada Hayden Heritage Park
        ];

        var nestsByUsername = new Dictionary<string, Waypoint>();
        foreach (var (username, latitude, longitude) in homeBases)
        {
            var user = users[username];
            // "{Username}'s Roost" rather than a shared literal "Home Base" for everyone - each
            // nest name is unique (so nest pickers/dropdowns in the app are distinguishable across
            // seeded users) while still following one common template.
            var nestName = $"{username}'s Roost";
            var waypoint = new Waypoint(
                Guid.NewGuid().ToString(),
                user.Id,
                nestName,
                latitude,
                longitude,
                DateTimeOffset.UtcNow,
                IsPublic: false);
            await waypointsContainer.CreateItemAsync(waypoint, new PartitionKey(waypoint.UserId));
            nestsByUsername[username] = waypoint;
            Console.WriteLine($"  + {nestName} at ({latitude}, {longitude})");
        }

        // Every user's starter roster (see BirdTypeCatalog.StarterRoster / BirdService.ListAsync)
        // seeded directly at their new Roost rather than left for lazy GET /birds provisioning -
        // a dev user's first bird-touching request wouldn't otherwise be the lazy-provisioning
        // codepath, since the account and nest already exist by the time anyone logs in.
        var rosterNow = DateTimeOffset.UtcNow;
        foreach (var username in usernames)
        {
            var user = users[username];
            var nest = nestsByUsername[username];
            foreach (var (type, count) in BirdTypeCatalog.StarterRoster)
            {
                for (var i = 1; i <= count; i++)
                {
                    var name = count > 1 ? $"{username}'s {type} {i}" : $"{username}'s {type}";
                    var bird = new Bird(
                        Guid.NewGuid().ToString(),
                        user.Id,
                        name,
                        CurrentNestId: nest.Id,
                        IsTraveling: false,
                        NestFromId: null,
                        NestToId: null,
                        Speed: null,
                        Content: null,
                        Type: type,
                        DepartedAt: null,
                        EstimatedArrivalAt: null,
                        IsRead: true,
                        UpdatedAt: rosterNow);
                    await birdsContainer.CreateItemAsync(bird, new PartitionKey(bird.UserId));
                }
            }
            Console.WriteLine($"  + {username}'s starter roster (2 Cro, 1 Raven, 1 Pigeon, 1 Parrot) at {nest.Name}");
        }

        Console.WriteLine("Done - all 5 users are friends with each other, each with a uniquely-named Roost nest around Ames and a full starter roster of 5 birds.");
    }
}
