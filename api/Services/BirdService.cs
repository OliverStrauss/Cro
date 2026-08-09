using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

public class BirdService(IBirdRepository birdRepository) : IBirdService
{
    private const int BirdsPerUser = 3;

    public async Task<List<Bird>> ListAsync(string userId)
    {
        var existing = await birdRepository.ListByUserIdAsync(userId);
        if (existing.Count > 0)
        {
            return existing;
        }

        // Lazy provisioning: some users predate this feature and have zero birds, and every
        // new registration also hits this path the first time it calls GET /birds - keeping
        // creation here (not in POST /users) means there's exactly one place that ever
        // creates a Bird document.
        var created = new List<Bird>();
        for (var i = 1; i <= BirdsPerUser; i++)
        {
            var bird = new Bird(
                Guid.NewGuid().ToString(),
                userId,
                $"Bird {i}",
                CurrentNestId: null,
                IsTraveling: false,
                NestFromId: null,
                NestToId: null,
                Speed: null,
                Content: null,
                DateTimeOffset.UtcNow);
            created.Add(await birdRepository.CreateAsync(bird));
        }
        return created;
    }

    public async Task AssignUnassignedBirdsToNestAsync(string userId, string nestId)
    {
        var birds = await birdRepository.ListByUserIdAsync(userId);
        foreach (var bird in birds.Where(b => b.CurrentNestId is null))
        {
            var updated = bird with { CurrentNestId = nestId, UpdatedAt = DateTimeOffset.UtcNow };
            await birdRepository.UpdateAsync(updated);
        }
    }
}
