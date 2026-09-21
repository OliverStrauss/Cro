using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosBotProfileRepository
{
    private readonly Container _container;

    public CosmosBotProfileRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.BotProfilesContainerName);
    }

    public async Task<BotProfile?> GetAsync(string userId)
    {
        try
        {
            var response = await _container.ReadItemAsync<BotProfile>(userId, new PartitionKey(userId));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    // Cross-partition - BotOrchestratorService's tick sweep needs every enabled bot
    // regardless of owner, same "small, scanned every sweep" shape as BirdRepository's
    // ListPublicTravelingAsync. Fine at this project's bot-roster scale; not something a
    // per-user index would help with the way GetAsync's point read already doesn't need one.
    public async Task<List<BotProfile>> ListEnabledAsync()
    {
        var query = _container.GetItemQueryIterator<BotProfile>(
            new QueryDefinition("SELECT * FROM c WHERE c.isEnabled = true"));

        var results = new List<BotProfile>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<BotProfile> CreateAsync(BotProfile profile)
    {
        var response = await _container.CreateItemAsync(profile, new PartitionKey(profile.UserId));
        return response.Resource;
    }

    public async Task<BotProfile> UpdateAsync(BotProfile profile)
    {
        var response = await _container.UpsertItemAsync(profile, new PartitionKey(profile.UserId));
        return response.Resource;
    }
}
