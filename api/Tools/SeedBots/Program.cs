using CroApp.Api.Services;
using Microsoft.Azure.Cosmos;

// Seeds the BotPersonaCatalog bots into a real Cosmos account (additive, never wipes) and
// befriends each username passed as an argument. Usage, from /api:
//   COSMOS_CONNECTION_STRING="<prod connection string>" dotnet run --project Tools/SeedBots -- Oliver
// Container names below must match CosmosDbOptions' defaults.
var connectionString = Environment.GetEnvironmentVariable("COSMOS_CONNECTION_STRING")
    ?? throw new InvalidOperationException("Set COSMOS_CONNECTION_STRING.");

using var client = new CosmosClient(connectionString, new CosmosClientOptions
{
    SerializerOptions = new CosmosSerializationOptions { PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase },
    ConnectionMode = ConnectionMode.Gateway,
});
var database = client.GetDatabase("CroApp");

await BotSeeder.EnsureBotsAsync(database, "Users", "Waypoints", "Birds", "BotProfiles");
foreach (var username in args)
{
    await BotSeeder.BefriendAsync(database, "Users", username);
}
