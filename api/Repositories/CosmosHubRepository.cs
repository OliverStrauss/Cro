using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosHubRepository : IHubRepository
{
    private readonly Container _container;

    public CosmosHubRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.HubsContainerName);
    }

    public async Task<List<Hub>> ListApprovedAsync()
    {
        // Single-partition - Status is the partition key, and this is the dominant query.
        var query = _container.GetItemQueryIterator<Hub>(
            new QueryDefinition("SELECT * FROM c WHERE c.status = @status")
                .WithParameter("@status", HubStatus.Approved),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(HubStatus.Approved) });

        var results = new List<Hub>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<List<Hub>> ListByStatusAsync(string status)
    {
        // Single-partition - same shape as ListApprovedAsync, generalized to any status
        // (currently just Approved and Pending).
        var query = _container.GetItemQueryIterator<Hub>(
            new QueryDefinition("SELECT * FROM c WHERE c.status = @status")
                .WithParameter("@status", status),
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(status) });

        var results = new List<Hub>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Hub?> GetAsync(string hubId)
    {
        // Cross-partition - a caller resolving a bird's destination-by-id doesn't know the
        // Hub's status up front, same reasoning as CosmosBirdRepository.GetByIdAsync. Fine
        // at the small row counts a curated Hub list has.
        var query = _container.GetItemQueryIterator<Hub>(
            new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", hubId));

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

    public async Task<Hub> CreateAsync(Hub hub)
    {
        var response = await _container.CreateItemAsync(hub, new PartitionKey(hub.Status));
        return response.Resource;
    }

    // Status (the partition key) never changes here - only used to update fields like
    // ProfilePictureUrl on an already-Approved Hub (see HubPictureService.ApproveAsync).
    public async Task<Hub> UpdateAsync(Hub hub)
    {
        var response = await _container.UpsertItemAsync(hub, new PartitionKey(hub.Status));
        return response.Resource;
    }

    public async Task DeleteAsync(string hubId, string status)
    {
        await _container.DeleteItemAsync<Hub>(hubId, new PartitionKey(status));
    }
}
