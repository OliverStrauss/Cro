using CroApp.Api.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.Azure.Cosmos;
using User = CroApp.Api.Models.User;

namespace CroApp.Api.Services;

// Additive, idempotent counterpart to DevDataSeeder's bot seeding - safe against a real
// account because it only ever inserts a bot that doesn't exist yet (matched by username)
// and never wipes anything. Runs on startup in every environment once a DeepInfra key is
// configured (see Program.cs), and from Tools/SeedBots. A bot gets the same shape
// DevDataSeeder gives one: IsBot User, one private Roost nest, the starter bird roster, and
// an enabled BotProfile. Friendships are NOT created here - real users befriend a bot
// through the normal request flow, which FriendService auto-accepts for IsBot targets.
public static class BotSeeder
{
    public static async Task EnsureBotsAsync(Database database, string usersContainerName, string waypointsContainerName, string birdsContainerName, string botProfilesContainerName)
    {
        var users = database.GetContainer(usersContainerName);
        var waypoints = database.GetContainer(waypointsContainerName);
        var birds = database.GetContainer(birdsContainerName);
        var botProfiles = database.GetContainer(botProfilesContainerName);
        var hasher = new PasswordHasher<User>();
        var personas = BotPersonaCatalog.Seeded;

        for (var index = 0; index < personas.Length; index++)
        {
            var (username, persona, model) = personas[index];
            if (await FindByUsernameAsync(users, username) is not null)
            {
                continue;
            }

            var user = new User(
                Guid.NewGuid().ToString(),
                username,
                // .invalid is reserved (RFC 2606) - can never collide with or reach a real mailbox.
                $"{username.ToLowerInvariant()}@bots.invalid",
                DateTimeOffset.UtcNow,
                PasswordHash: "",
                Friends: [],
                IsBot: true,
                IsEmailVerified: true);
            // Random throwaway password nobody knows - a bot is never logged into.
            user = user with { PasswordHash = hasher.HashPassword(user, Guid.NewGuid().ToString("N")) };
            await users.CreateItemAsync(user, new PartitionKey(user.Id));

            var (latitude, longitude) = DevDataSeeder.AmesSpiralPoint(index, personas.Length);
            var nest = new Waypoint(Guid.NewGuid().ToString(), user.Id, $"{username}'s Roost", latitude, longitude, DateTimeOffset.UtcNow, IsPublic: false);
            await waypoints.CreateItemAsync(nest, new PartitionKey(nest.UserId));
            await DevDataSeeder.SeedStarterRosterAsync(birds, user, nest);

            var profile = new BotProfile(user.Id, user.Id, persona, model, IsEnabled: true, ConsecutiveBotReplies: [], LastTickAt: null, UpdatedAt: DateTimeOffset.UtcNow);
            await botProfiles.CreateItemAsync(profile, new PartitionKey(profile.UserId));
            Console.WriteLine($"Seeded bot {username} (id: {user.Id})");
        }
    }

    // Makes every bot Accepted-friends with `humanUsername` right now, both sides written -
    // the same end state FriendService.SendRequestAsync + AcceptAsync produce, for one-off
    // use by Tools/SeedBots (no JWT/HTTP needed against a real account). Throws if the human
    // doesn't exist so a typo can't silently do nothing.
    public static async Task BefriendAsync(Database database, string usersContainerName, string humanUsername)
    {
        var users = database.GetContainer(usersContainerName);
        var human = await FindByUsernameAsync(users, humanUsername)
            ?? throw new InvalidOperationException($"No user named '{humanUsername}'.");

        foreach (var (botUsername, _, _) in BotPersonaCatalog.Seeded)
        {
            var bot = await FindByUsernameAsync(users, botUsername)
                ?? throw new InvalidOperationException($"Bot '{botUsername}' not seeded yet - run EnsureBotsAsync first.");
            var humanFriends = human.Friends ?? [];
            var botFriends = bot.Friends ?? [];
            if (humanFriends.Any(f => f.Id == bot.Id && f.Status == FriendStatus.Accepted))
            {
                continue;
            }

            // Replace any stale pending entry rather than duplicating it.
            humanFriends = [.. humanFriends.Where(f => f.Id != bot.Id), new FriendEntry(bot.Id, bot.Username, FriendStatus.Accepted, FriendColorPalette.PickNext(humanFriends.Where(f => f.Color is not null).Select(f => f.Color!)))];
            botFriends = [.. botFriends.Where(f => f.Id != human.Id), new FriendEntry(human.Id, human.Username, FriendStatus.Accepted, FriendColorPalette.PickNext(botFriends.Where(f => f.Color is not null).Select(f => f.Color!)))];
            human = human with { Friends = humanFriends };
            await users.ReplaceItemAsync(human, human.Id, new PartitionKey(human.Id));
            await users.ReplaceItemAsync(bot with { Friends = botFriends }, bot.Id, new PartitionKey(bot.Id));
            Console.WriteLine($"{humanUsername} <-> {botUsername} are now friends");
        }
    }

    private static async Task<User?> FindByUsernameAsync(Container users, string username)
    {
        var query = users.GetItemQueryIterator<User>(new QueryDefinition("SELECT * FROM c WHERE c.username = @u").WithParameter("@u", username));
        while (query.HasMoreResults)
        {
            var match = (await query.ReadNextAsync()).FirstOrDefault();
            if (match is not null)
            {
                return match;
            }
        }
        return null;
    }
}
