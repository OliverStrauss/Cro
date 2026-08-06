using System.Net;
using CroApp.Api.Data;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;
using User = CroApp.Api.Models.User;

namespace CroApp.Api.Repositories;

public class CosmosUserRepository : IUserRepository
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
}
