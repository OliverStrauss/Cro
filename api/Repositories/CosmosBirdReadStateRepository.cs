using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosBirdReadStateRepository
{
    private readonly Container _container;

    public CosmosBirdReadStateRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.BirdReadStatesContainerName);
    }

    public async Task<List<BirdReadState>> ListForUserAsync(string userId)
    {
        // Single-partition - UserId is the partition key.
        var query = _container.GetItemQueryIterator<BirdReadState>(
            new QueryDefinition("SELECT * FROM c WHERE c.userId = @userId")
                .WithParameter("@userId", userId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(userId) });

        var results = new List<BirdReadState>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task MarkReadAsync(string userId, string birdId, DateTimeOffset readAt)
    {
        var state = new BirdReadState($"{userId}:{birdId}", userId, birdId, readAt);
        await _container.UpsertItemAsync(state, new PartitionKey(userId));
    }
}
