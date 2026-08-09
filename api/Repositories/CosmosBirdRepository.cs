using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosBirdRepository : IBirdRepository
{
    private readonly Container _container;

    public CosmosBirdRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.BirdsContainerName);
    }

    public async Task<List<Bird>> ListByUserIdAsync(string userId)
    {
        var query = _container.GetItemQueryIterator<Bird>(
            new QueryDefinition("SELECT * FROM c WHERE c.userId = @userId").WithParameter("@userId", userId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(userId) });

        var results = new List<Bird>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Bird> CreateAsync(Bird bird)
    {
        var response = await _container.CreateItemAsync(bird, new PartitionKey(bird.UserId));
        return response.Resource;
    }

    public async Task<Bird> UpdateAsync(Bird bird)
    {
        var response = await _container.UpsertItemAsync(bird, new PartitionKey(bird.UserId));
        return response.Resource;
    }
}
