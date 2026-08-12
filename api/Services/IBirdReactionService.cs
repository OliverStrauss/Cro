namespace CroApp.Api.Services;

public record BirdReactionSummaryEntry(string Emoji, int Count, bool ReactedByMe);

public interface IBirdReactionService
{
    Task<List<BirdReactionSummaryEntry>> GetSummaryAsync(string callerId, string birdId);
    Task AddAsync(string callerId, string birdId, string emoji);
    Task RemoveAsync(string callerId, string birdId, string emoji);
}
