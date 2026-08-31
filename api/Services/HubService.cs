using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public class HubService(IHubRepository hubRepository) : IHubService
{
    public Task<List<Hub>> ListApprovedAsync() => hubRepository.ListApprovedAsync();

    public async Task<Hub> CreateAsync(string createdByUserId, string name, double latitude, double longitude, string category)
    {
        var hub = new Hub(
            Guid.NewGuid().ToString(),
            name,
            latitude,
            longitude,
            HubStatus.Approved,
            createdByUserId,
            DateTimeOffset.UtcNow,
            category);
        return await hubRepository.CreateAsync(hub);
    }

    public async Task<Hub> GetAsync(string hubId) =>
        await hubRepository.GetAsync(hubId) ?? throw new HubServiceException(404, "Hub not found.");

    public async Task<Hub> SuggestAsync(string suggestedByUserId, string name, double latitude, double longitude, string category)
    {
        var hub = new Hub(
            Guid.NewGuid().ToString(),
            name,
            latitude,
            longitude,
            HubStatus.Pending,
            suggestedByUserId,
            DateTimeOffset.UtcNow,
            category);
        return await hubRepository.CreateAsync(hub);
    }

    public Task<List<Hub>> ListPendingAsync() => hubRepository.ListByStatusAsync(HubStatus.Pending);

    // Status is the partition key, so "approving" can't be an in-place update - the Pending
    // doc is deleted and recreated in the Approved partition, reusing the same Id for
    // continuity.
    public async Task<Hub> ApproveAsync(string hubId)
    {
        var pending = await hubRepository.GetAsync(hubId)
            ?? throw new HubServiceException(404, "Suggestion not found.");
        if (pending.Status != HubStatus.Pending)
        {
            throw new HubServiceException(409, "This hub is not a pending suggestion.");
        }

        await hubRepository.DeleteAsync(pending.Id, HubStatus.Pending);
        var approved = pending with { Status = HubStatus.Approved };
        return await hubRepository.CreateAsync(approved);
    }

    public async Task RejectAsync(string hubId)
    {
        var pending = await hubRepository.GetAsync(hubId)
            ?? throw new HubServiceException(404, "Suggestion not found.");
        if (pending.Status != HubStatus.Pending)
        {
            throw new HubServiceException(409, "This hub is not a pending suggestion.");
        }

        await hubRepository.DeleteAsync(pending.Id, HubStatus.Pending);
    }
}
