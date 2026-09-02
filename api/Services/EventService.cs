using CroApp.Api.Models;
using CroApp.Api.Repositories;
using Microsoft.Extensions.Logging;

namespace CroApp.Api.Services;

public class EventService(
    CosmosEventRepository eventRepository,
    CosmosWaypointRepository waypointRepository,
    ILogger<EventService> logger)
{
    public Task RecordBirdDepartedAsync(Bird bird) => RecordBestEffortAsync(async () =>
    {
        await CreateAsync(
            bird.UserId,
            EventKind.BirdDeparted,
            $"{bird.Name} left {bird.NestFromName ?? "its nest"} for {bird.NestToName ?? "its destination"}",
            isNotification: false,
            targetType: EventTargetType.Bird,
            targetId: bird.Id);
    }, nameof(RecordBirdDepartedAsync), bird.Id);

    public Task RecordBirdArrivalAsync(Bird arrivedBird) => RecordBestEffortAsync(async () =>
    {
        var destinationName = arrivedBird.NestToName ?? "its destination";

        // A bird that landed back at one of its own owner's nests (a resend loop, or simply
        // its only reachable destination) reads as "returned" rather than "arrived at" -
        // otherwise every arrival reads the same regardless of whose nest it landed at.
        var destinationNest = arrivedBird.NestToId is null
            ? null
            : await waypointRepository.GetByIdAsync(arrivedBird.NestToId);
        var isOwnNest = destinationNest is not null && destinationNest.UserId == arrivedBird.UserId;

        await CreateAsync(
            arrivedBird.UserId,
            EventKind.BirdArrived,
            isOwnNest
                ? $"{arrivedBird.Name} returned from {arrivedBird.NestFromName ?? "its journey"}"
                : $"{arrivedBird.Name} arrived at {destinationName}",
            isNotification: true,
            targetType: EventTargetType.Bird,
            targetId: arrivedBird.Id);

        // Only the destination nest's owner gets a separate "arrived at your nest"
        // notification, and only when that owner isn't the sender themselves (handled by
        // the BirdArrived entry above already).
        if (destinationNest is not null && destinationNest.UserId != arrivedBird.UserId)
        {
            await CreateAsync(
                destinationNest.UserId,
                EventKind.BirdArrivedAtYourNest,
                $"{arrivedBird.Name} arrived at your {destinationName}",
                isNotification: true,
                targetType: EventTargetType.Nest,
                targetId: destinationNest.Id);
        }
    }, nameof(RecordBirdArrivalAsync), arrivedBird.Id);

    public Task RecordHubPostAsync(Bird arrivedBird, Hub hub) => RecordBestEffortAsync(async () =>
    {
        await CreateAsync(
            arrivedBird.UserId,
            EventKind.HubPostCreated,
            $"{arrivedBird.Name} posted to the {hub.Name} board",
            isNotification: false,
            targetType: EventTargetType.Hub,
            targetId: hub.Id,
            quotedNote: arrivedBird.Content);
    }, nameof(RecordHubPostAsync), arrivedBird.Id);

    public Task RecordBirdJoinedFlockAsync(Bird newBird) => RecordBestEffortAsync(async () =>
    {
        await CreateAsync(
            newBird.UserId,
            EventKind.BirdJoinedFlock,
            $"{newBird.Name} joined your flock",
            isNotification: false,
            targetType: EventTargetType.Bird,
            targetId: newBird.Id);
    }, nameof(RecordBirdJoinedFlockAsync), newBird.Id);

    public Task RecordFriendAddedAsync(User acceptor, User requester) => RecordBestEffortAsync(async () =>
    {
        await CreateAsync(
            acceptor.Id,
            EventKind.FriendAdded,
            $"You and {requester.Username} are now friends",
            isNotification: false);

        await CreateAsync(
            requester.Id,
            EventKind.FriendRequestAccepted,
            $"{acceptor.Username} accepted your friend request",
            isNotification: true);
    }, nameof(RecordFriendAddedAsync), acceptor.Id);

    public Task<List<Event>> ListTimelineAsync(string userId, int limit) =>
        eventRepository.ListByUserIdAsync(userId, limit);

    public Task<List<Event>> ListNotificationsAsync(string userId, int limit) =>
        eventRepository.ListNotificationsByUserIdAsync(userId, limit);

    public Task<int> CountUnreadNotificationsAsync(string userId) =>
        eventRepository.CountUnreadNotificationsAsync(userId);

    public async Task MarkNotificationReadAsync(string userId, string eventId)
    {
        var evt = await eventRepository.GetAsync(userId, eventId)
            ?? throw new ServiceException(404, "Notification not found.");
        if (!evt.IsRead)
        {
            await eventRepository.UpdateAsync(evt with { IsRead = true });
        }
    }

    public async Task MarkAllNotificationsReadAsync(string userId)
    {
        var unread = (await eventRepository.ListNotificationsByUserIdAsync(userId, int.MaxValue))
            .Where(e => !e.IsRead);
        foreach (var evt in unread)
        {
            await eventRepository.UpdateAsync(evt with { IsRead = true });
        }
    }

    private Task CreateAsync(
        string userId,
        string kind,
        string displayText,
        bool isNotification,
        string? targetType = null,
        string? targetId = null,
        string? quotedNote = null) =>
        eventRepository.CreateAsync(new Event(
            Guid.NewGuid().ToString(),
            userId,
            kind,
            displayText,
            quotedNote,
            targetType,
            targetId,
            isNotification,
            IsRead: !isNotification,
            DateTimeOffset.UtcNow));

    // Shared best-effort wrapper for every Record* method - a broken event write (a missing
    // container in some test config, a transient Cosmos hiccup) must never fail the bird
    // send/arrival/friend-accept it's describing. Same philosophy as the pre-existing
    // try/catch around HubMessage creation in BirdService.ResolveArrivalIfDueAsync.
    private async Task RecordBestEffortAsync(Func<Task> action, string operation, string subjectId)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to record event ({Operation}) for {SubjectId}", operation, subjectId);
        }
    }
}
