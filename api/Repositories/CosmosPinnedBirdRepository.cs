using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosPinnedBirdRepository
{
    private readonly Container _container;

    public CosmosPinnedBirdRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.PinsContainerName);
    }

    public async Task<List<PinnedBird>> ListByReceiverIdAsync(string receiverId)
    {
        // Single-partition - ReceiverId is the partition key. Newest-first, same convention
        // as HubMessage's board query.
        var query = _container.GetItemQueryIterator<PinnedBird>(
            new QueryDefinition("SELECT * FROM c WHERE c.receiverId = @receiverId ORDER BY c.createdAt DESC")
                .WithParameter("@receiverId", receiverId),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(receiverId) });

        var results = new List<PinnedBird>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    // ponytail: full cross-partition scan of every public pin in the Pins container, ordered
    // in memory - fine at this project's user-base scale, same tradeoff BirdService.
    // ListPublicInTransitAsync already accepts for GET /birds/public. Upgrade path if this
    // container ever gets large: a composite index on (isPublic, createdAt) so the ORDER BY
    // can run server-side, or a materialized "public pins" view.
    public async Task<List<PinnedBird>> ListPublicAsync()
    {
        // Cross-partition - a public pin can belong to any receiver, same shape as
        // CosmosBirdRepository.ListPublicTravelingAsync.
        var query = _container.GetItemQueryIterator<PinnedBird>(
            new QueryDefinition("SELECT * FROM c WHERE c.isPublic = true"));

        var results = new List<PinnedBird>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results.OrderByDescending(p => p.CreatedAt).ToList();
    }

    public async Task<PinnedBird?> GetByIdAsync(string id)
    {
        // Cross-partition - a caller acting on a pin (unpinning, taking one down) doesn't
        // necessarily know the receiver's id, same reasoning as CosmosBirdRepository.GetByIdAsync.
        var query = _container.GetItemQueryIterator<PinnedBird>(
            new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", id));

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

    // Upsert, not create - PinnedBird.Id is deterministic per delivery (see PinnedBird.BuildId),
    // so re-pinning the same still-resident delivery replaces the same row instead of
    // conflicting, same idempotent-toggle shape as CosmosBirdReactionRepository.UpsertAsync.
    public async Task<PinnedBird> UpsertAsync(PinnedBird pin)
    {
        var response = await _container.UpsertItemAsync(pin, new PartitionKey(pin.ReceiverId));
        return response.Resource;
    }

    public async Task<bool> DeleteAsync(string receiverId, string id)
    {
        try
        {
            await _container.DeleteItemAsync<PinnedBird>(id, new PartitionKey(receiverId));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }
}
