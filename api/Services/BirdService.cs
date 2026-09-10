using CroApp.Api.Data;
using CroApp.Api.Models;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

public class BirdService(
    CosmosBirdRepository birdRepository,
    CosmosWaypointRepository waypointRepository,
    CosmosUserRepository userRepository,
    CosmosHubRepository hubRepository,
    CosmosHubMessageRepository hubMessageRepository,
    BirdMediaService birdMediaService,
    EventService eventService,
    IOptions<BirdTravelOptions> birdTravelOptions,
    ILogger<BirdService> logger)
{
    private const int MaxBirdsPerUser = 5;

    public async Task<List<Bird>> ListAsync(string userId)
    {
        var existing = await birdRepository.ListByUserIdAsync(userId);
        if (existing.Count == 0)
        {
            existing = await ProvisionStarterRosterAsync(userId);
        }
        var resolved = new List<Bird>();
        foreach (var bird in existing)
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        return resolved;
    }

    // Every user starts with the fixed BirdTypeCatalog.StarterRoster instead of spawning
    // birds themselves - lazily provisioned on first GET /birds (mirrors this app's older
    // auto-provisioning flow) rather than at POST /users, so there's exactly one place that
    // ever creates a starter Bird document. Nestless (CurrentNestId: null) until
    // AssignUnassignedBirdsToNestAsync attaches them to the nest the user creates next - a
    // brand-new user has no nest yet at this point.
    private async Task<List<Bird>> ProvisionStarterRosterAsync(string userId)
    {
        var owner = await userRepository.GetByIdAsync(userId);
        var ownerName = owner?.Username ?? "Your";
        var now = DateTimeOffset.UtcNow;

        var created = new List<Bird>();
        foreach (var (type, count) in BirdTypeCatalog.StarterRoster)
        {
            for (var i = 1; i <= count; i++)
            {
                var name = count > 1 ? $"{ownerName}'s {type} {i}" : $"{ownerName}'s {type}";
                var bird = new Bird(
                    Guid.NewGuid().ToString(),
                    userId,
                    name,
                    CurrentNestId: null,
                    IsTraveling: false,
                    NestFromId: null,
                    NestToId: null,
                    Speed: null,
                    Content: null,
                    Type: type,
                    DepartedAt: null,
                    EstimatedArrivalAt: null,
                    IsRead: true,
                    UpdatedAt: now);
                created.Add(await birdRepository.CreateAsync(bird));
            }
        }
        return created;
    }

    // Attaches any of the caller's nestless birds (the starter roster, provisioned with
    // CurrentNestId: null before the owner had a nest to place them in) to the nest they just
    // created. Called from POST /waypoints - lives there rather than inside WaypointService so
    // Waypoint doesn't take on a dependency on Bird, same composition-at-the-endpoint pattern
    // as GET /friends/waypoints.
    public async Task AssignUnassignedBirdsToNestAsync(string userId, string nestId)
    {
        var birds = await birdRepository.ListByUserIdAsync(userId);
        foreach (var bird in birds.Where(b => b.CurrentNestId is null && !b.IsTraveling))
        {
            await birdRepository.UpdateAsync(bird with { CurrentNestId = nestId, UpdatedAt = DateTimeOffset.UtcNow });
        }
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

    // Multi-friend analog of ListTravelingAsync for GET /friends/birds - fetches every
    // given user's birds in a single cross-partition query instead of one ListByUserIdAsync
    // round trip per friend, same batching GetManyByUserIdsAsync already gives waypoints.
    // Arrival resolution still runs one bird at a time since each can trigger its own write.
    public async Task<List<Bird>> ListTravelingForUsersAsync(IEnumerable<string> userIds)
    {
        var existing = await birdRepository.GetManyByUserIdsAsync(userIds);
        var resolved = new List<Bird>();
        foreach (var bird in existing.Where(b => b.IsTraveling))
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        return resolved.Where(b => b.IsTraveling).ToList();
    }

    // Spawns a brand-new bird and sends it in one step. No longer reachable from the product
    // UI - every user is auto-provisioned BirdTypeCatalog.StarterRoster instead (see
    // ProvisionStarterRosterAsync) and MaxBirdsPerUser means a normal user is already at the
    // cap, so this 409s for them same as any other over-cap attempt. Left in place (endpoint
    // still wired, see Program.cs) purely as the test suite's way of getting a bird into a
    // specific state - see TECH_DEBT.md. The origin must be caller-owned (unlike SendAsync's
    // resend flow, a new bird can't depart from a friend's nest or a Hub); the destination can
    // be anywhere reachable (own, a friend's, or a Hub).
    public async Task<Bird> ComposeAndSendAsync(
        string userId,
        string type,
        string name,
        string originNestId,
        string destinationId,
        string? content,
        bool isPublic,
        Stream? mediaStream,
        string? mediaContentType,
        long mediaContentLength)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ServiceException(400, "This bird needs a name.");
        }
        if (!BirdTypeCatalog.IsValid(type))
        {
            throw new ServiceException(400, $"Unknown bird type '{type}'.");
        }

        var existing = await birdRepository.ListByUserIdAsync(userId);
        if (existing.Count >= MaxBirdsPerUser)
        {
            throw new ServiceException(409, $"You can have at most {MaxBirdsPerUser} birds. Delete one (from your private nest) before spawning another.");
        }

        BirdPayloadValidator.Validate(type, content, mediaStream is not null);

        var origin = await waypointRepository.GetAsync(userId, originNestId)
            ?? throw new ServiceException(404, "Origin nest not found - a new bird can only depart from one of your own nests.");
        var destination = await ResolveReachableNestAsync(userId, destinationId)
            ?? throw new ServiceException(404, "Destination not found.");
        if (origin.Id == destination.Id)
        {
            throw new ServiceException(400, "Pick a different destination than the origin nest.");
        }

        var birdId = Guid.NewGuid().ToString();
        string? audioUrl = null;
        string? imageUrl = null;
        if (mediaStream is not null)
        {
            var mediaKind = BirdPayloadValidator.MediaKindForType(type);
            var mediaUrl = await birdMediaService.UploadAsync(birdId, mediaKind, mediaStream, mediaContentType ?? "", mediaContentLength);
            if (mediaKind == BirdMediaKind.Audio)
            {
                audioUrl = mediaUrl;
            }
            else
            {
                imageUrl = mediaUrl;
            }
        }

        var distanceKm = GeoDistance.HaversineKm(origin.Latitude, origin.Longitude, destination.Latitude, destination.Longitude);
        var effectiveSpeedKmh = BirdTypeCatalog.BaseSpeedKmh(type) * birdTravelOptions.Value.SpeedMultiplier;
        var hours = effectiveSpeedKmh > 0 ? distanceKm / effectiveSpeedKmh : 0;

        var now = DateTimeOffset.UtcNow;
        var bird = new Bird(
            birdId,
            userId,
            name.Trim(),
            CurrentNestId: null,
            IsTraveling: true,
            NestFromId: origin.Id,
            NestToId: destination.Id,
            Speed: effectiveSpeedKmh,
            Content: content,
            Type: type,
            DepartedAt: now,
            EstimatedArrivalAt: now.AddHours(hours),
            IsRead: true, // not delivered yet - nothing to read
            UpdatedAt: now,
            AudioUrl: audioUrl,
            ImageUrl: imageUrl,
            ProfilePictureUrl: null,
            // A Hub-bound bird can stay private - the compose form's toggle is respected the
            // same as for any other destination. The Hub message board (see HubMessage.cs)
            // always shows every arrival regardless of this flag; IsPublic only controls
            // masking on the live "who's here" view (GetHubResidentBirds).
            IsPublic: isPublic,
            NestFromName: origin.Name,
            NestToName: destination.Name);
        var created = await birdRepository.CreateAsync(bird);
        await eventService.RecordBirdDepartedAsync(created);
        await eventService.RecordBirdJoinedFlockAsync(created);
        return created;
    }

    // Resends an already-landed, caller-owned bird onward - distinct from ComposeAndSendAsync
    // (spawning a brand-new bird). A bird can be resent from wherever it currently sits
    // (its own nest, or a friend's/Hub's it previously arrived at), unlike a newly-composed
    // bird's origin, which must be caller-owned. Each leg's payload (content/media) replaces
    // the previous one rather than carrying it forward - same as ComposeAndSendAsync, a leg
    // with nothing new to say just travels with no payload.
    public async Task<Bird> SendAsync(
        string userId,
        string birdId,
        string destinationNestId,
        string? content,
        Stream? mediaStream,
        string? mediaContentType,
        long mediaContentLength)
    {
        var bird = await birdRepository.GetAsync(userId, birdId)
            ?? throw new ServiceException(404, "Bird not found.");
        bird = await ResolveArrivalIfDueAsync(bird);

        if (bird.IsTraveling)
        {
            throw new ServiceException(409, "This bird is already traveling.");
        }
        if (bird.CurrentNestId is null)
        {
            throw new ServiceException(400, "This bird has no current nest to depart from.");
        }
        if (bird.CurrentNestId == destinationNestId)
        {
            throw new ServiceException(400, "This bird is already at that nest.");
        }

        BirdPayloadValidator.ValidateAllowed(bird.Type, content, mediaStream is not null);

        var destination = await ResolveReachableNestAsync(userId, destinationNestId)
            ?? throw new ServiceException(404, "Destination nest not found.");
        // Origin may be a friend's nest or a Hub the bird previously arrived at, not
        // necessarily one the caller owns - resolve the same way as the destination, not a
        // plain owner-scoped lookup.
        var origin = await ResolveReachableNestAsync(userId, bird.CurrentNestId)
            ?? throw new ServiceException(404, "Origin nest not found.");

        string? audioUrl = null;
        string? imageUrl = null;
        if (mediaStream is not null)
        {
            var mediaKind = BirdPayloadValidator.MediaKindForType(bird.Type);
            var mediaUrl = await birdMediaService.UploadAsync(bird.Id, mediaKind, mediaStream, mediaContentType ?? "", mediaContentLength);
            if (mediaKind == BirdMediaKind.Audio)
            {
                audioUrl = mediaUrl;
            }
            else
            {
                imageUrl = mediaUrl;
            }
        }

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
            AudioUrl = audioUrl,
            ImageUrl = imageUrl,
            // A resend keeps the bird's existing IsPublic value, same as ComposeAndSendAsync -
            // a Hub-bound resend no longer forces it true (see that method's comment).
            IsPublic = bird.IsPublic,
            NestFromName = origin.Name,
            NestToName = destination.Name,
        };
        var saved = await birdRepository.UpdateAsync(updated);
        await eventService.RecordBirdDepartedAsync(saved);
        return saved;
    }

    public async Task<Bird> RenameAsync(string userId, string birdId, string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ServiceException(400, "This bird needs a name.");
        }

        var bird = await birdRepository.GetAsync(userId, birdId)
            ?? throw new ServiceException(404, "Bird not found.");
        var updated = bird with { Name = name.Trim(), UpdatedAt = DateTimeOffset.UtcNow };
        return await birdRepository.UpdateAsync(updated);
    }

    // Only allowed once a bird is idle specifically at the owner's PRIVATE nest - not the
    // public one, not a friend's, not a Hub. Frees a slot in the MaxBirdsPerUser cap.
    public async Task DeleteAsync(string userId, string birdId)
    {
        var bird = await birdRepository.GetAsync(userId, birdId)
            ?? throw new ServiceException(404, "Bird not found.");
        bird = await ResolveArrivalIfDueAsync(bird);

        if (bird.IsTraveling)
        {
            throw new ServiceException(409, "This bird is still traveling.");
        }

        var privateNest = (await waypointRepository.ListByUserIdAsync(userId)).FirstOrDefault(w => !w.IsPublic);
        if (privateNest is null || bird.CurrentNestId != privateNest.Id)
        {
            throw new ServiceException(409, "This bird can only be deleted once it's home at your private nest.");
        }

        var deleted = await birdRepository.DeleteAsync(userId, birdId);
        if (!deleted)
        {
            throw new ServiceException(404, "Bird not found.");
        }
    }

    public async Task<List<Bird>> GetNestResidentsAsync(string userId, string nestId)
    {
        var nest = await waypointRepository.GetAsync(userId, nestId)
            ?? throw new ServiceException(404, "Nest not found.");

        var candidates = await birdRepository.GetByNestIdAsync(nest.Id);
        var resolved = new List<Bird>();
        foreach (var bird in candidates)
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        // Drop still-inbound birds that were only fetched so resolution could run on them.
        // Newest arrival first - UpdatedAt is set to the moment a bird actually lands (see
        // ResolveArrivalIfDueAsync), same "most recent first" convention as a Hub's message
        // board (CosmosHubMessageRepository's ORDER BY c.createdAt DESC).
        return resolved.Where(b => b.CurrentNestId == nest.Id).OrderByDescending(b => b.UpdatedAt).ToList();
    }

    // Hub analog of GetNestResidentsAsync, deliberately without an owner-gate - nobody owns
    // a Hub, so anyone can see who's currently sitting at a public landmark.
    public async Task<List<Bird>> GetHubResidentsAsync(string hubId)
    {
        var hub = await hubRepository.GetAsync(hubId)
            ?? throw new ServiceException(404, "Hub not found.");

        var candidates = await birdRepository.GetByNestIdAsync(hub.Id);
        var resolved = new List<Bird>();
        foreach (var bird in candidates)
        {
            resolved.Add(await ResolveArrivalIfDueAsync(bird));
        }
        return resolved.Where(b => b.CurrentNestId == hub.Id).OrderByDescending(b => b.UpdatedAt).ToList();
    }

    public async Task<Bird> MarkReadAsync(string userId, string birdId)
    {
        var bird = await birdRepository.GetByIdAsync(birdId)
            ?? throw new ServiceException(404, "Bird not found.");
        bird = await ResolveArrivalIfDueAsync(bird);

        var nest = await waypointRepository.GetAsync(userId, bird.CurrentNestId ?? string.Empty);
        if (bird.CurrentNestId is null || nest is null)
        {
            // Caller doesn't own the nest this bird currently sits in (or it's mid-flight,
            // nowhere yet) - same "don't leak details" 404 as the nest-residents endpoint.
            throw new ServiceException(404, "Bird not found.");
        }

        var updated = bird with { IsRead = true, UpdatedAt = DateTimeOffset.UtcNow };
        return await birdRepository.UpdateAsync(updated);
    }

    // A point the caller can act on as an origin/destination: their own nest (point read),
    // an accepted friend's nest, or a Hub - projected to a common shape since Waypoint and
    // Hub are different types and neither should take on a dependency on the other just for
    // this. Reused for both SendAsync's origin/destination resolution and
    // ComposeAndSendAsync's destination resolution (never its origin, which must be
    // caller-owned).
    private async Task<ReachablePoint?> ResolveReachableNestAsync(string userId, string nestId)
    {
        var own = await waypointRepository.GetAsync(userId, nestId);
        if (own is not null)
        {
            return new ReachablePoint(own.Id, own.Latitude, own.Longitude, own.Name, IsHub: false);
        }

        var caller = await userRepository.GetByIdAsync(userId);
        var friendIds = (caller?.Friends ?? [])
            .Where(f => f.Status == FriendStatus.Accepted)
            .Select(f => f.Id);
        var friendNests = await waypointRepository.GetManyByUserIdsAsync(friendIds);
        var friendNest = friendNests.FirstOrDefault(w => w.Id == nestId);
        if (friendNest is not null)
        {
            return new ReachablePoint(friendNest.Id, friendNest.Latitude, friendNest.Longitude, friendNest.Name, IsHub: false);
        }

        var hub = await hubRepository.GetAsync(nestId);
        return hub is not null ? new ReachablePoint(hub.Id, hub.Latitude, hub.Longitude, hub.Name, IsHub: true) : null;
    }

    private record ReachablePoint(string Id, double Latitude, double Longitude, string Name, bool IsHub);

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
        arrived = await birdRepository.UpdateAsync(arrived);
        await eventService.RecordBirdArrivalAsync(arrived);

        // No IsPublic check here - every arrival at a Hub is board-worthy regardless of
        // whether the bird itself is public (see GET /hubs/{id}/messages in Program.cs).
        // Best-effort: a failed board write must never fail the caller's actual query just
        // because this secondary write hiccuped.
        var landedHub = await hubRepository.GetAsync(arrived.NestToId ?? string.Empty);
        if (landedHub is not null)
        {
            try
            {
                var sender = await userRepository.GetByIdAsync(arrived.UserId);
                await hubMessageRepository.CreateAsync(new HubMessage(
                    Guid.NewGuid().ToString(),
                    landedHub.Id,
                    arrived.Id,
                    arrived.UserId,
                    sender?.Username ?? "Unknown",
                    arrived.Name,
                    arrived.NestFromName,
                    arrived.Type,
                    arrived.Content,
                    arrived.AudioUrl,
                    arrived.ImageUrl,
                    DateTimeOffset.UtcNow));
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to post HubMessage for bird {BirdId} landing at hub {HubId}", arrived.Id, landedHub.Id);
            }

            await eventService.RecordHubPostAsync(arrived, landedHub);
        }

        return arrived;
    }
}
