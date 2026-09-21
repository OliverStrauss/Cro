using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

// Turns a delivered bird into a durable PinnedBird snapshot - see PinnedBird.cs for why this
// needs to exist at all (a HubMessage is the only other durable record a bird's content ever
// gets, and only Hub arrivals get one). Deliberately its own service rather than folded into
// BirdService, same separation BirdReactionService already draws from BirdService.
public class PinService(
    CosmosBirdRepository birdRepository,
    CosmosWaypointRepository waypointRepository,
    CosmosUserRepository userRepository,
    CosmosPinnedBirdRepository pinRepository,
    EventService eventService)
{
    public async Task<PinnedBird> PinAsync(string userId, string birdId)
    {
        var bird = await birdRepository.GetByIdAsync(birdId)
            ?? throw new ServiceException(404, "Bird not found.");

        if (bird.UserId == userId)
        {
            throw new ServiceException(400, "You can't pin your own bird.");
        }

        // Same ownership check as BirdService.MarkReadAsync: the bird must currently be
        // sitting, arrived, at a nest the caller owns - not mid-flight, not at a Hub (which
        // already gets its own durable HubMessage), not someone else's nest.
        var nest = await waypointRepository.GetAsync(userId, bird.CurrentNestId ?? string.Empty);
        if (bird.CurrentNestId is null || nest is null)
        {
            throw new ServiceException(404, "Bird not found.");
        }

        var sender = await userRepository.GetByIdAsync(bird.UserId);
        var receiver = await userRepository.GetByIdAsync(userId);

        var pin = new PinnedBird(
            PinnedBird.BuildId(bird.Id, userId, bird.UpdatedAt),
            userId,
            bird.UserId,
            sender?.Username ?? "Unknown",
            bird.Id,
            bird.Name,
            bird.NestFromName,
            nest.Id,
            bird.Type,
            bird.Content,
            bird.AudioUrl,
            bird.ImageUrl,
            bird.IsPublic,
            DateTimeOffset.UtcNow);

        var saved = await pinRepository.UpsertAsync(pin);
        // A bot's pins are its conversation log, not a gesture - don't tell a human "Pixel
        // pinned your message" on every single message they send it.
        if (receiver?.IsBot != true)
        {
            await eventService.RecordBirdPinnedAsync(saved, receiver?.Username ?? "Someone");
        }
        return saved;
    }

    public Task<List<PinnedBird>> ListMineAsync(string userId) => pinRepository.ListByReceiverIdAsync(userId);

    public Task<List<PinnedBird>> ListPublicAsync() => pinRepository.ListPublicAsync();

    // Whether THIS specific delivery (not just this bird - see PinnedBird.BuildId, a reused
    // bird gets a fresh id every delivery) is already pinned by the caller - same deterministic
    // id PinAsync would upsert to, so this is a pure lookup with no write. Lets the client show
    // real pinned state on open instead of always starting from "unpinned" (a bird that isn't
    // currently resident has no "current delivery" to ask about, hence the same 404 PinAsync uses).
    public async Task<PinnedBird?> GetForCurrentDeliveryAsync(string userId, string birdId)
    {
        var bird = await birdRepository.GetByIdAsync(birdId)
            ?? throw new ServiceException(404, "Bird not found.");

        var id = PinnedBird.BuildId(bird.Id, userId, bird.UpdatedAt);
        return await pinRepository.GetByIdAsync(id);
    }

    // One verb for both "the receiver unpins their own saved message" and "the sender takes
    // down a public pin of their own bird" - a private pin can only ever be removed by the
    // receiver who made it, since nobody else can even see it.
    public async Task UnpinAsync(string userId, string pinId)
    {
        var pin = await pinRepository.GetByIdAsync(pinId)
            ?? throw new ServiceException(404, "Pin not found.");

        var canRemove = pin.ReceiverId == userId || (pin.IsPublic && pin.SenderId == userId);
        if (!canRemove)
        {
            throw new ServiceException(404, "Pin not found.");
        }

        await pinRepository.DeleteAsync(pin.ReceiverId, pinId);
    }
}
