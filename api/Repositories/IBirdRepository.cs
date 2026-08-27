using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IBirdRepository
{
    Task<List<Bird>> ListByUserIdAsync(string userId);
    Task<Bird?> GetAsync(string userId, string birdId);
    Task<Bird?> GetByIdAsync(string birdId);
    Task<List<Bird>> GetByNestIdAsync(string nestId);
    Task<Bird> CreateAsync(Bird bird);
    Task<Bird> UpdateAsync(Bird bird);
    Task<bool> DeleteAsync(string userId, string birdId);
}
