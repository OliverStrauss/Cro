using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IUserRepository
{
    Task<User> CreateAsync(User user);
    Task<User?> GetByIdAsync(string id);
    Task<User?> GetByUsernameAsync(string username);
    Task<List<User>> SearchByUsernamePrefixAsync(string prefix, int limit);
    Task<User> UpdateAsync(User user);
}
