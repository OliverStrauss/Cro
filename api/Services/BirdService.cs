using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class BirdService(
    IBirdRepository birdRepository,
    IWaypointRepository waypointRepository,
    IUserRepository userRepository,
    IOptions<BirdTravelOptions> birdTravelOptions) : IBirdService
{
    private const int BirdsPerUser = 3;

    public async Task<List<Bird>> ListAsync(string userId)
    {
        var existing = await birdRepository.ListByUserIdAsync(userId);
        if (existing.Count == 0)
        {
            existing = await ProvisionBirdsAsync(userId);
        }

        var resolved = new List<Bird>();
        foreach (var bird in existing)
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        return resolved;
    }

    // Friends'-birds-on-the-map support: unlike ListAsync, this deliberately does NOT
    // provision - a friend with zero birds simply has none traveling, and viewing someone
    // else's map shouldn't have the side effect of creating bird documents in their
    // account. Still resolves arrivals so a friend's just-landed bird doesn't show as
    // traveling for a few extra seconds compared to their own GET /birds view of it.
    public async Task<List<Bird>> ListTravelingAsync(string userId)
    {
        var existing = await birdRepository.ListByUserIdAsync(userId);
        var resolved = new List<Bird>();
        foreach (var bird in existing.Where(b => b.IsTraveling))
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        return resolved.Where(b => b.IsTraveling).ToList();
    }

    // Lazy provisioning: some users predate this feature and have zero birds, and every
    // new registration also hits this path the first time it calls GET /birds - keeping
    // creation here (not in POST /users) means there's exactly one place that ever
    // creates a Bird document.
    private async Task<List<Bird>> ProvisionBirdsAsync(string userId)
    {
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
                Type: BirdTypeCatalog.PickForSlot(i - 1),
                DepartedAt: null,
                EstimatedArrivalAt: null,
                IsRead: true,
                DateTimeOffset.UtcNow);
            created.Add(await birdRepository.CreateAsync(bird));
        }
        return created;
    }

    public async Task AssignUnassignedBirdsToNestAsync(string userId, string nestId)
    {
        var birds = await birdRepository.ListByUserIdAsync(userId);
        foreach (var bird in birds.Where(b => b.CurrentNestId is null && !b.IsTraveling))
        {
            var updated = bird with { CurrentNestId = nestId, UpdatedAt = DateTimeOffset.UtcNow };
            await birdRepository.UpdateAsync(updated);
        }
    }

    public async Task<Bird> SendAsync(string userId, string birdId, string destinationNestId, string? content)
    {
        var bird = await birdRepository.GetAsync(userId, birdId)
            ?? throw new BirdServiceException(404, "Bird not found.");
        bird = await ResolveArrivalIfDueAsync(bird);

        if (bird.IsTraveling)
        {
            throw new BirdServiceException(409, "This bird is already traveling.");
        }
        if (bird.CurrentNestId is null)
        {
            throw new BirdServiceException(400, "This bird has no current nest to depart from.");
        }
        if (bird.CurrentNestId == destinationNestId)
        {
            throw new BirdServiceException(400, "This bird is already at that nest.");
        }

        var destination = await ResolveReachableNestAsync(userId, destinationNestId)
            ?? throw new BirdServiceException(404, "Destination nest not found.");
        // Origin may be a friend's nest the bird previously arrived at, not necessarily one
        // the caller owns - resolve the same way as the destination, not a plain owner-scoped
        // lookup.
        var origin = await ResolveReachableNestAsync(userId, bird.CurrentNestId)
            ?? throw new BirdServiceException(404, "Origin nest not found.");

        var distanceKm = GeoDistance.HaversineKm(origin.Latitude, origin.Longitude, destination.Latitude, destination.Longitude);
        var effectiveSpeedKmh = BirdTypeCatalog.BaseSpeedKmh(bird.Type) * birdTravelOptions.Value.SpeedMultiplier;
        var hours = effectiveSpeedKmh > 0 ? distanceKm / effectiveSpeedKmh : 0;

        var now = DateTimeOffset.UtcNow;
        var updated = bird with
        {
            CurrentNestId = null,
            IsTraveling = true,
            NestFromId = origin.Id,
            NestToId = destination.Id,
            Speed = effectiveSpeedKmh,
            Content = content,
            DepartedAt = now,
            EstimatedArrivalAt = now.AddHours(hours),
            IsRead = true, // not delivered yet - nothing to read
            UpdatedAt = now,
        };
        return await birdRepository.UpdateAsync(updated);
    }

    public async Task<List<Bird>> GetNestResidentsAsync(string userId, string nestId)
    {
        var nest = await waypointRepository.GetAsync(userId, nestId)
            ?? throw new BirdServiceException(404, "Nest not found.");

        var candidates = await birdRepository.GetByNestIdAsync(nest.Id);
        var resolved = new List<Bird>();
        foreach (var bird in candidates)
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        // Drop still-inbound birds that were only fetched so resolution could run on them.
        return resolved.Where(b => b.CurrentNestId == nest.Id).ToList();
    }

    public async Task<Bird> MarkReadAsync(string userId, string birdId)
    {
        var bird = await birdRepository.GetByIdAsync(birdId)
            ?? throw new BirdServiceException(404, "Bird not found.");
        bird = await ResolveArrivalIfDueAsync(bird);

        var nest = await waypointRepository.GetAsync(userId, bird.CurrentNestId ?? string.Empty);
        if (bird.CurrentNestId is null || nest is null)
        {
            // Caller doesn't own the nest this bird currently sits in (or it's mid-flight,
            // nowhere yet) - same "don't leak details" 404 as the nest-residents endpoint.
            throw new BirdServiceException(404, "Bird not found.");
        }

        var updated = bird with { IsRead = true, UpdatedAt = DateTimeOffset.UtcNow };
        return await birdRepository.UpdateAsync(updated);
    }

    // A nest the caller can act on: their own (point read), or an accepted friend's - same
    // lookup GET /friends/waypoints already does, reused here for send/origin validation.
    private async Task<Waypoint?> ResolveReachableNestAsync(string userId, string nestId)
    {
        var own = await waypointRepository.GetAsync(userId, nestId);
        if (own is not null)
        {
            return own;
        }

        var caller = await userRepository.GetByIdAsync(userId);
        var friendIds = (caller?.Friends ?? [])
            .Where(f => f.Status == FriendStatus.Accepted)
            .Select(f => f.Id);
        var friendNests = await waypointRepository.GetManyByUserIdsAsync(friendIds);
        return friendNests.FirstOrDefault(w => w.Id == nestId);
    }

    // Flips a bird from "traveling" to "arrived" if its ETA has passed, persisting the
    // change. This is the only place arrival is ever detected - there's no timer/background
    // job, so it only happens as a side effect of some query touching the bird (GET /birds
    // for the owner's own list, or GET /waypoints/{id}/birds for a nest's residents). A bird
    // that's arrived-but-unresolved simply keeps reporting IsTraveling=true/CurrentNestId=null
    // to anyone who hasn't queried it yet, and gets caught the next time someone does.
    private async Task<Bird> ResolveArrivalIfDueAsync(Bird bird)
    {
        if (!bird.IsTraveling || bird.EstimatedArrivalAt is null || DateTimeOffset.UtcNow < bird.EstimatedArrivalAt)
        {
            return bird;
        }

        var arrived = bird with
        {
            CurrentNestId = bird.NestToId,
            IsTraveling = false,
            IsRead = false, // any arrival is unread, no sender/recipient special-casing
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        return await birdRepository.UpdateAsync(arrived);
    }
}
