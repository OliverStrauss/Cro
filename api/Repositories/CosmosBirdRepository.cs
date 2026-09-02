using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosBirdRepository
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

    public async Task<List<Bird>> GetManyByUserIdsAsync(IEnumerable<string> userIds)
    {
        var ids = userIds.ToList();
        if (ids.Count == 0)
        {
            return [];
        }

        // Cross-partition query - friends' birds span many different userId partitions, so
        // this can't be scoped to a single PartitionKey the way ListByUserIdAsync is. Same
        // ARRAY_CONTAINS shape as CosmosWaypointRepository.GetManyByUserIdsAsync, used to
        // fetch every accepted friend's birds in one round trip instead of one per friend.
        var query = _container.GetItemQueryIterator<Bird>(
            new QueryDefinition("SELECT * FROM c WHERE ARRAY_CONTAINS(@userIds, c.userId)")
                .WithParameter("@userIds", ids));

        var results = new List<Bird>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Bird?> GetAsync(string userId, string birdId)
    {
        try
        {
            var response = await _container.ReadItemAsync<Bird>(birdId, new PartitionKey(userId));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<Bird?> GetByIdAsync(string birdId)
    {
        // Cross-partition - the caller (e.g. a nest owner marking a delivered bird read)
        // doesn't necessarily know the bird's owning userId, so this can't be a point read.
        var query = _container.GetItemQueryIterator<Bird>(
            new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", birdId));

        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            var match = page.FirstOrDefault();
            if (match is not null)
            {
                return match;
            }
        }
        return null;
    }

    public async Task<List<Bird>> GetByNestIdAsync(string nestId)
    {
        // Cross-partition - a nest's residents can be owned by many different users. The
        // nestToId half of the OR catches birds that are due to arrive but haven't been
        // flipped over to currentNestId yet (see BirdService.ResolveArrivalIfDueAsync).
        var query = _container.GetItemQueryIterator<Bird>(
            new QueryDefinition("SELECT * FROM c WHERE c.currentNestId = @nestId OR c.nestToId = @nestId")
                .WithParameter("@nestId", nestId));

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

    public async Task<bool> DeleteAsync(string userId, string birdId)
    {
        try
        {
            await _container.DeleteItemAsync<Bird>(birdId, new PartitionKey(userId));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }
}
