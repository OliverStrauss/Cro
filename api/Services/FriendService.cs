using CroApp.Api.Models;
using CroApp.Api.Repositories;

namespace CroApp.Api.Services;

// send/accept/remove each write two separate User documents with no cross-document
// transaction - Cosmos has none across partitions/documents here. A crash mid-operation
// can leave one side stale. Same accepted-tradeoff category as Waypoint's bare
// UpsertItemAsync with no ETag concurrency checks; not worth a saga/compensation pattern
// at this project's scale.
public class FriendService(IUserRepository userRepository, IEventService eventService) : IFriendService
{
    public async Task SendRequestAsync(string requesterId, string targetUsername)
    {
        var requester = await userRepository.GetByIdAsync(requesterId)
            ?? throw new FriendServiceException(404, "Requesting user not found.");

        var target = await userRepository.GetByUsernameAsync(targetUsername)
            ?? throw new FriendServiceException(404, "No user with that username.");

        if (target.Id == requester.Id)
        {
            throw new FriendServiceException(400, "Cannot send a friend request to yourself.");
        }

        var requesterFriends = requester.Friends ?? [];
        if (requesterFriends.Any(f => f.Id == target.Id))
        {
            throw new FriendServiceException(409, "A relationship with this user already exists.");
        }

        if ((requester.BlockedUserIds ?? []).Contains(target.Id) || (target.BlockedUserIds ?? []).Contains(requester.Id))
        {
            throw new FriendServiceException(403, "Cannot send a request to this user.");
        }

        var targetFriends = target.Friends ?? [];

        var updatedRequester = requester with
        {
            Friends = [.. requesterFriends, new FriendEntry(target.Id, target.Username, FriendStatus.PendingOutgoing, null)]
        };
        var updatedTarget = target with
        {
            Friends = [.. targetFriends, new FriendEntry(requester.Id, requester.Username, FriendStatus.PendingIncoming, null)]
        };

        await userRepository.UpdateAsync(updatedRequester);
        await userRepository.UpdateAsync(updatedTarget);
    }

    public async Task AcceptAsync(string userId, string requesterId)
    {
        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");
        var requester = await userRepository.GetByIdAsync(requesterId)
            ?? throw new FriendServiceException(404, "Requesting user not found.");

        var userFriends = user.Friends ?? [];
        var requesterFriends = requester.Friends ?? [];

        var incomingEntry = userFriends.FirstOrDefault(f => f.Id == requesterId && f.Status == FriendStatus.PendingIncoming);
        var outgoingEntry = requesterFriends.FirstOrDefault(f => f.Id == userId && f.Status == FriendStatus.PendingOutgoing);
        if (incomingEntry is null || outgoingEntry is null)
        {
            throw new FriendServiceException(400, "No pending friend request from this user.");
        }

        var userColor = FriendColorPalette.PickNext(userFriends
            .Where(f => f.Color is not null)
            .Select(f => f.Color!));
        var requesterColor = FriendColorPalette.PickNext(requesterFriends
            .Where(f => f.Color is not null)
            .Select(f => f.Color!));

        var updatedUserFriends = userFriends
            .Select(f => f.Id == requesterId ? f with { Status = FriendStatus.Accepted, Color = userColor } : f)
            .ToList();
        var updatedRequesterFriends = requesterFriends
            .Select(f => f.Id == userId ? f with { Status = FriendStatus.Accepted, Color = requesterColor } : f)
            .ToList();

        await userRepository.UpdateAsync(user with { Friends = updatedUserFriends });
        await userRepository.UpdateAsync(requester with { Friends = updatedRequesterFriends });
        await eventService.RecordFriendAddedAsync(user, requester);
    }

    public async Task RemoveAsync(string userId, string otherUserId)
    {
        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");

        var updatedUserFriends = (user.Friends ?? []).Where(f => f.Id != otherUserId).ToList();
        await userRepository.UpdateAsync(user with { Friends = updatedUserFriends });

        var other = await userRepository.GetByIdAsync(otherUserId);
        if (other is not null)
        {
            var updatedOtherFriends = (other.Friends ?? []).Where(f => f.Id != userId).ToList();
            await userRepository.UpdateAsync(other with { Friends = updatedOtherFriends });
        }
    }

    // A distinct first-class action rather than reusing RemoveAsync directly - the
    // underlying removal is identical (declining a pending request just deletes the entry
    // from both sides, same as removing an accepted friend), but a separate endpoint/method
    // keeps client intent explicit and gives declining its own hook, independent from
    // "remove an existing friend" or "cancel my own outgoing request".
    public Task DeclineAsync(string userId, string requesterId) => RemoveAsync(userId, requesterId);

    public async Task BlockAsync(string userId, string targetId)
    {
        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");

        if (userId == targetId)
        {
            throw new FriendServiceException(400, "Cannot block yourself.");
        }

        var blocked = user.BlockedUserIds ?? [];
        if (!blocked.Contains(targetId))
        {
            await userRepository.UpdateAsync(user with { BlockedUserIds = [.. blocked, targetId] });
        }

        // Blocking also clears any existing/pending relationship, same as RemoveAsync -
        // there's no reason a block should coexist with a stale friend entry either side.
        await RemoveAsync(userId, targetId);
    }

    public async Task UnblockAsync(string userId, string targetId)
    {
        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");

        var updatedBlocked = (user.BlockedUserIds ?? []).Where(id => id != targetId).ToList();
        await userRepository.UpdateAsync(user with { BlockedUserIds = updatedBlocked });
    }

    public async Task<List<string>> ListBlockedAsync(string userId)
    {
        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");

        return user.BlockedUserIds ?? [];
    }

    public async Task SetColorAsync(string userId, string friendId, string color)
    {
        if (!FriendColorPalette.Colors.Contains(color))
        {
            throw new FriendServiceException(400, "Not a valid palette color.");
        }

        var user = await userRepository.GetByIdAsync(userId)
            ?? throw new FriendServiceException(404, "User not found.");

        var friends = user.Friends ?? [];
        var entry = friends.FirstOrDefault(f => f.Id == friendId && f.Status == FriendStatus.Accepted);
        if (entry is null)
        {
            throw new FriendServiceException(404, "Not a current friend.");
        }

        var updatedFriends = friends
            .Select(f => f.Id == friendId ? f with { Color = color } : f)
            .ToList();

        await userRepository.UpdateAsync(user with { Friends = updatedFriends });
    }
}
