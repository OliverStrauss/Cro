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
}
