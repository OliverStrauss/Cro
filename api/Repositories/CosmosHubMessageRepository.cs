using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosHubMessageRepository : IHubMessageRepository
{
    private readonly Container _container;

    public CosmosHubMessageRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.HubMessagesContainerName);
    }

    public async Task<List<HubMessage>> ListByHubIdAsync(string hubId)
    {
        // Single-partition - HubId is the partition key. Newest-first for the board's
        // chronological timeline.
        var query = _container.GetItemQueryIterator<HubMessage>(
            new QueryDefinition("SELECT * FROM c WHERE c.hubId = @hubId ORDER BY c.createdAt DESC")
                .WithParameter("@hubId", hubId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(hubId) });

        var results = new List<HubMessage>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<HubMessage> CreateAsync(HubMessage message)
    {
        var response = await _container.CreateItemAsync(message, new PartitionKey(message.HubId));
        return response.Resource;
    }
}
