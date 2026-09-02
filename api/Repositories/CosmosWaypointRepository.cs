using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosWaypointRepository
{
    private readonly Container _container;

    public CosmosWaypointRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.WaypointsContainerName);
    }

    public async Task<List<Waypoint>> ListByUserIdAsync(string userId)
    {
        var query = _container.GetItemQueryIterator<Waypoint>(
            new QueryDefinition("SELECT * FROM c WHERE c.userId = @userId").WithParameter("@userId", userId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(userId) });

        var results = new List<Waypoint>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Waypoint?> GetAsync(string userId, string waypointId)
    {
        try
        {
            var response = await _container.ReadItemAsync<Waypoint>(waypointId, new PartitionKey(userId));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<Waypoint?> GetByIdAsync(string waypointId)
    {
        // Cross-partition - EventService looks up a bird's destination nest by id alone to
        // find its owner, the same "caller doesn't know the owning userId" situation
        // CosmosBirdRepository.GetByIdAsync already handles for Bird.
        var query = _container.GetItemQueryIterator<Waypoint>(
            new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", waypointId));

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

    public async Task<Waypoint> CreateAsync(Waypoint waypoint)
    {
        var response = await _container.CreateItemAsync(waypoint, new PartitionKey(waypoint.UserId));
        return response.Resource;
    }

    public async Task<Waypoint> UpdateAsync(Waypoint waypoint)
    {
        var response = await _container.UpsertItemAsync(waypoint, new PartitionKey(waypoint.UserId));
        return response.Resource;
    }

    public async Task<bool> DeleteAsync(string userId, string waypointId)
    {
        try
        {
            await _container.DeleteItemAsync<Waypoint>(waypointId, new PartitionKey(userId));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    public async Task<List<Waypoint>> GetManyByUserIdsAsync(IEnumerable<string> userIds)
    {
        var ids = userIds.ToList();
        if (ids.Count == 0)
        {
            return [];
        }

        // Cross-partition query - friends' nests span many different userId partitions, so
        // this can't be scoped to a single PartitionKey the way ListByUserIdAsync is.
        var query = _container.GetItemQueryIterator<Waypoint>(
            new QueryDefinition("SELECT * FROM c WHERE ARRAY_CONTAINS(@userIds, c.userId)")
                .WithParameter("@userIds", ids));

        var results = new List<Waypoint>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }
}
