using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosHubPictureSuggestionRepository : IHubPictureSuggestionRepository
{
    private readonly Container _container;

    public CosmosHubPictureSuggestionRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.HubPictureSuggestionsContainerName);
    }

    public async Task<HubPictureSuggestion> CreateAsync(HubPictureSuggestion suggestion)
    {
        var response = await _container.CreateItemAsync(suggestion, new PartitionKey(suggestion.HubId));
        return response.Resource;
    }

    // Cross-partition - this container only ever holds pending rows (approving/rejecting
    // deletes the row outright), so "list pending" is just "list everything". Fine at the
    // small row counts a curated Hub's photo suggestions have, same tradeoff category as
    // CosmosHubRepository.GetAsync below.
    public async Task<List<HubPictureSuggestion>> ListPendingAsync()
    {
        var query = _container.GetItemQueryIterator<HubPictureSuggestion>("SELECT * FROM c");
        var results = new List<HubPictureSuggestion>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }
        return results;
    }

    // Cross-partition - the approve/reject endpoints only know the suggestion's own id, not
    // which Hub it targets, same reasoning as CosmosHubRepository.GetAsync(hubId).
    public async Task<HubPictureSuggestion?> GetAsync(string suggestionId)
    {
        var query = _container.GetItemQueryIterator<HubPictureSuggestion>(
            new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", suggestionId));

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

    public async Task DeleteAsync(string suggestionId, string hubId)
    {
        await _container.DeleteItemAsync<HubPictureSuggestion>(suggestionId, new PartitionKey(hubId));
    }
}
