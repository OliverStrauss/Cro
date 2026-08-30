using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosEventRepository : IEventRepository
{
    private readonly Container _container;

    public CosmosEventRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.EventsContainerName);
    }

    public async Task<Event> CreateAsync(Event evt)
    {
        var response = await _container.CreateItemAsync(evt, new PartitionKey(evt.UserId));
        return response.Resource;
    }

    public async Task<List<Event>> ListByUserIdAsync(string userId, int limit)
    {
        var all = await QueryByUserIdAsync(userId);
        return [.. all.OrderByDescending(e => e.CreatedAt).Take(limit)];
    }

    public async Task<List<Event>> ListNotificationsByUserIdAsync(string userId, int limit)
    {
        var all = await QueryByUserIdAsync(userId);
        return [.. all.Where(e => e.IsNotification).OrderByDescending(e => e.CreatedAt).Take(limit)];
    }

    public async Task<int> CountUnreadNotificationsAsync(string userId)
    {
        var all = await QueryByUserIdAsync(userId);
        return all.Count(e => e.IsNotification && !e.IsRead);
    }

    public async Task<Event?> GetAsync(string userId, string eventId)
    {
        try
        {
            var response = await _container.ReadItemAsync<Event>(eventId, new PartitionKey(userId));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<Event> UpdateAsync(Event evt)
    {
        var response = await _container.UpsertItemAsync(evt, new PartitionKey(evt.UserId));
        return response.Resource;
    }

    // Single-partition (userId is the partition key), sorted/limited client-side rather than
    // via an ORDER BY + OFFSET/LIMIT query - this history is deliberately never pruned, so a
    // long-lived account's full event list could grow large, but adding a composite index
    // just to push the sort into Cosmos isn't worth it at this project's scale (same
    // accepted tradeoff FriendService's bare UpsertItemAsync calls already document).
    private async Task<List<Event>> QueryByUserIdAsync(string userId)
    {
        var query = _container.GetItemQueryIterator<Event>(
            new QueryDefinition("SELECT * FROM c WHERE c.userId = @userId").WithParameter("@userId", userId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(userId) });

        var results = new List<Event>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }
}
