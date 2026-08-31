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
// "{Username}'s Roost" nest around Ames, plus a few seed Birds sent between them. Users is
// wiped and replaced; Waypoints and Birds only ever get new rows added, never wiped (so
// locally-placed Hubs and any manually-sent birds survive a re-run) - Hubs and Reactions are
// left exactly as they are.
public static class DevDataSeeder
{
    private const string Password = "1";

    public static async Task SeedFixedDevUsersAsync(Database database, string usersContainerName, string waypointsContainerName, string birdsContainerName)
    {
        var usersContainer = database.GetContainer(usersContainerName);
        var waypointsContainer = database.GetContainer(waypointsContainerName);
        var birdsContainer = database.GetContainer(birdsContainerName);

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

        // A handful of Cro's between friends so the app doesn't look empty right after a reset -
        // some still mid-flight, some already landed (one read, one not), touching every seeded user
        // as either sender or recipient at least once. Stuck to the Cro type only (plain text) so
        // this stays fully offline - Parrot/Pigeon/Raven would need real audio/image URLs to render
        // as anything but a broken-media placeholder in the app.
        //
        // ETAs are hand-picked rather than run through the real GeoDistance/BirdTypeCatalog math:
        // these seeded nests are deliberately clustered around Ames (see homeBases above) so pins
        // don't overlap, so a real distance/speed computation would land every "in-flight" bird
        // within minutes - not the sustained in-flight state the dock/journey log are meant to show.
        // Speed is still snapshotted at Cro's real base speed for field-shape consistency, it just
        // isn't what these particular ETAs were derived from.
        var now = DateTimeOffset.UtcNow;
        var croSpeedKmh = BirdTypeCatalog.BaseSpeedKmh(BirdTypeCatalog.Cro);

        (string FromUsername, string ToUsername, string Name, string Content, TimeSpan? EtaFromNow)[] seedBirds =
        [
            ("Oliver", "Annie", "Morning Cro", "Morning! Heading your way.", TimeSpan.FromHours(18)),
            ("Test1", "Test2", "Halfway There", "Made it past the stadium, halfway there!", TimeSpan.FromDays(2)),
            ("Test2", "Admin", "See You Soon", "On my way, see you soon.", TimeSpan.FromHours(6)),
            ("Admin", "Oliver", "Welcome", "Welcome to the flock!", null),
            ("Annie", "Test1", "Made It", "Made it safely, thanks for having me.", null),
        ];

        foreach (var (fromUsername, toUsername, name, content, etaFromNow) in seedBirds)
        {
            var sender = users[fromUsername];
            var origin = nestsByUsername[fromUsername];
            var destination = nestsByUsername[toUsername];
            var isTraveling = etaFromNow is not null;

            var bird = new Bird(
                Guid.NewGuid().ToString(),
                sender.Id,
                name,
                // Idle/arrived birds sit in the destination nest they landed in, same as
                // BirdService.ResolveArrivalIfDueAsync sets on real arrival resolution.
                CurrentNestId: isTraveling ? null : destination.Id,
                IsTraveling: isTraveling,
                NestFromId: origin.Id,
                NestToId: destination.Id,
                Speed: croSpeedKmh,
                Content: content,
                Type: BirdTypeCatalog.Cro,
                DepartedAt: isTraveling ? now : now.AddDays(-3),
                EstimatedArrivalAt: isTraveling ? now.Add(etaFromNow!.Value) : now.AddDays(-1),
                // Idle birds land unread, same as a real arrival - the "Welcome" one is left unread,
                // "Made It" is marked already-read for a bit of state variety.
                IsRead: isTraveling || name == "Made It",
                UpdatedAt: now,
                IsPublic: false,
                NestFromName: origin.Name);
            await birdsContainer.CreateItemAsync(bird, new PartitionKey(bird.UserId));
            Console.WriteLine($"  + {fromUsername} -> {toUsername}: \"{name}\" ({(isTraveling ? "in flight" : "arrived")})");
        }

        Console.WriteLine("Done - all 5 users are friends with each other, each with a uniquely-named Roost nest around Ames, plus a few Cro's already in flight or delivered.");
    }
}
