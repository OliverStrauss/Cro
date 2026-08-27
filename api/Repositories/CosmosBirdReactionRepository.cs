using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosBirdReactionRepository : IBirdReactionRepository
{
    private readonly Container _container;

    public CosmosBirdReactionRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.ReactionsContainerName);
    }

    public async Task<List<BirdReaction>> ListByBirdIdAsync(string birdId)
    {
        // Single-partition - BirdId is the partition key.
        var query = _container.GetItemQueryIterator<BirdReaction>(
            new QueryDefinition("SELECT * FROM c WHERE c.birdId = @birdId").WithParameter("@birdId", birdId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(birdId) });

        var results = new List<BirdReaction>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<BirdReaction> UpsertAsync(BirdReaction reaction)
    {
        var response = await _container.UpsertItemAsync(reaction, new PartitionKey(reaction.BirdId));
        return response.Resource;
    }

    public async Task<bool> DeleteAsync(string birdId, string reactionId)
    {
        try
        {
            await _container.DeleteItemAsync<BirdReaction>(reactionId, new PartitionKey(birdId));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }
}
