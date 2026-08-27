using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IBirdReactionRepository
{
    Task<List<BirdReaction>> ListByBirdIdAsync(string birdId);
    Task<BirdReaction> UpsertAsync(BirdReaction reaction);
    Task<bool> DeleteAsync(string birdId, string reactionId);
}
