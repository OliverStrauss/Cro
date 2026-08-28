using CroApp.Api.Models;

namespace CroApp.Api.Services;

// Every Record* method is called from inside BirdService/FriendService, right after the
// domain write it's describing already succeeded - and every one of them is best-effort
// (failures are caught and logged inside EventService itself, never thrown back to the
// caller), so a broken event write can never fail a bird send/arrival/friend-accept. The
// List/Count/Mark* methods back the actual read endpoints and behave normally (their
// failures do propagate - there's nothing else to protect there).
public interface IEventService
{
    Task RecordBirdDepartedAsync(Bird bird);
    Task RecordBirdArrivalAsync(Bird arrivedBird);
    Task RecordHubPostAsync(Bird arrivedBird, Hub hub);
    Task RecordBirdJoinedFlockAsync(Bird newBird);
    Task RecordFriendAddedAsync(User acceptor, User requester);

    Task<List<Event>> ListTimelineAsync(string userId, int limit);
    Task<List<Event>> ListNotificationsAsync(string userId, int limit);
    Task<int> CountUnreadNotificationsAsync(string userId);
    Task MarkNotificationReadAsync(string userId, string eventId);
    Task MarkAllNotificationsReadAsync(string userId);
}
