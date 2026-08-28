using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosHubReadStateRepository : IHubReadStateRepository
{
    private readonly Container _container;

    public CosmosHubReadStateRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.HubReadStatesContainerName);
    }

    public async Task<List<HubReadState>> ListForUserAsync(string userId)
    {
        // Single-partition - UserId is the partition key.
        var query = _container.GetItemQueryIterator<HubReadState>(
            new QueryDefinition("SELECT * FROM c WHERE c.userId = @userId")
                .WithParameter("@userId", userId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(userId) });

        var results = new List<HubReadState>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task MarkReadAsync(string userId, string hubId, DateTimeOffset readAt)
    {
        var state = new HubReadState($"{userId}:{hubId}", userId, hubId, readAt);
        await _container.UpsertItemAsync(state, new PartitionKey(userId));
    }
}
