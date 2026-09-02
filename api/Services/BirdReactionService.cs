using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public record BirdReactionSummaryEntry(string Emoji, int Count, bool ReactedByMe);

public class BirdReactionService(CosmosBirdReactionRepository reactionRepository, CosmosBirdRepository birdRepository)
{
    public async Task<List<BirdReactionSummaryEntry>> GetSummaryAsync(string callerId, string birdId)
    {
        await EnsurePublicBirdExistsAsync(birdId);
        var reactions = await reactionRepository.ListByBirdIdAsync(birdId);
        return reactions
            .GroupBy(r => r.Emoji)
            .Select(g => new BirdReactionSummaryEntry(g.Key, g.Count(), g.Any(r => r.UserId == callerId)))
            .OrderByDescending(e => e.Count)
            .ToList();
    }

    public async Task AddAsync(string callerId, string birdId, string emoji)
    {
        if (!BirdReactionEmoji.Allowed.Contains(emoji))
        {
            throw new ServiceException(400, "Unsupported reaction.");
        }
        await EnsurePublicBirdExistsAsync(birdId);

        var reaction = new BirdReaction(BirdReaction.BuildId(birdId, callerId, emoji), birdId, callerId, emoji, DateTimeOffset.UtcNow);
        await reactionRepository.UpsertAsync(reaction);
    }

    // Idempotent - deleting a reaction that was never added (or already removed) is a no-op,
    // not an error, same "don't make the caller check first" ergonomics as the add path's
    // upsert.
    public async Task RemoveAsync(string callerId, string birdId, string emoji)
    {
        var id = BirdReaction.BuildId(birdId, callerId, emoji);
        await reactionRepository.DeleteAsync(birdId, id);
    }

    private async Task EnsurePublicBirdExistsAsync(string birdId)
    {
        var bird = await birdRepository.GetByIdAsync(birdId)
            ?? throw new ServiceException(404, "Bird not found.");
        if (!bird.IsPublic)
        {
            throw new ServiceException(400, "Only public birds can be reacted to.");
        }
    }
}
