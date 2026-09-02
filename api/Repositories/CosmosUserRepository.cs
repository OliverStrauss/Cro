using System.Net;
using CroApp.Api.Data;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using User = CroApp.Api.Models.User;

namespace CroApp.Api.Repositories;

public class CosmosUserRepository
{
    private readonly Container _container;

    public CosmosUserRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.UsersContainerName);
    }

    public async Task<User> CreateAsync(User user)
    {
        var response = await _container.CreateItemAsync(user, new PartitionKey(user.Id));
        return response.Resource;
    }

    public async Task<User?> GetByIdAsync(string id)
    {
        try
        {
            var response = await _container.ReadItemAsync<User>(id, new PartitionKey(id));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<User?> GetByUsernameAsync(string username)
    {
        // Cross-partition query: partition key is /id, not /username. Fine at current tiny
        // user counts; a dedicated username lookup would be a future perf item if needed.
        var query = _container.GetItemQueryIterator<User>(
            new QueryDefinition("SELECT * FROM c WHERE c.username = @username")
                .WithParameter("@username", username));

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

    // Case-insensitive username-prefix search, for the "Add Friends" live-suggestions
    // dropdown. Cross-partition query, same tradeoff as GetByUsernameAsync above - fine at
    // current tiny user counts. Stops paging as soon as `limit` results are in hand rather
    // than always exhausting the query, so a broad prefix on a larger user base doesn't
    // page through every match just to throw most of them away.
    public async Task<List<User>> SearchByUsernamePrefixAsync(string prefix, int limit)
    {
        var query = _container.GetItemQueryIterator<User>(
            new QueryDefinition("SELECT * FROM c WHERE STARTSWITH(c.username, @prefix, true)")
                .WithParameter("@prefix", prefix));

        var results = new List<User>();
        while (query.HasMoreResults && results.Count < limit)
        {
            var page = await query.ReadNextAsync();
            results.AddRange(page);
        }

        return results.Take(limit).ToList();
    }

    public async Task<User> UpdateAsync(User user)
    {
        var response = await _container.UpsertItemAsync(user, new PartitionKey(user.Id));
        return response.Resource;
    }
}
