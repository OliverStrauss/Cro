using System.Net;
using CroApp.Api.Data;
using CroApp.Api.Models;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Repositories;

public class CosmosWaypointRepository : IWaypointRepository
{
    private readonly Container _container;

    public CosmosWaypointRepository(CosmosClient client, IOptions<CosmosDbOptions> options)
    {
        var opts = options.Value;
        _container = client.GetContainer(opts.DatabaseName, opts.WaypointsContainerName);
    }

    public async Task<Waypoint?> GetByUserIdAsync(string userId)
    {
        try
        {
            var response = await _container.ReadItemAsync<Waypoint>(userId, new PartitionKey(userId));
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<Waypoint> UpsertAsync(Waypoint waypoint)
    {
        var response = await _container.UpsertItemAsync(waypoint, new PartitionKey(waypoint.Id));
        return response.Resource;
    }
}
