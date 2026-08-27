using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IHubMessageRepository
{
    Task<List<HubMessage>> ListByHubIdAsync(string hubId);
    Task<HubMessage> CreateAsync(HubMessage message);
}
