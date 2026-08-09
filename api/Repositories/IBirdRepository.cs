using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IBirdRepository
{
    Task<List<Bird>> ListByUserIdAsync(string userId);
    Task<Bird> CreateAsync(Bird bird);
    Task<Bird> UpdateAsync(Bird bird);
}
