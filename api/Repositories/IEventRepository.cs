using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IEventRepository
{
    Task<Event> CreateAsync(Event evt);
    Task<List<Event>> ListByUserIdAsync(string userId, int limit);
    Task<List<Event>> ListNotificationsByUserIdAsync(string userId, int limit);
    Task<int> CountUnreadNotificationsAsync(string userId);
    Task<Event?> GetAsync(string userId, string eventId);
    Task<Event> UpdateAsync(Event evt);
}
