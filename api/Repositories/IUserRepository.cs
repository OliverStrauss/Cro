using CroApp.Api.Models;

namespace CroApp.Api.Repositories;

public interface IUserRepository
{
    Task<User> CreateAsync(User user);
    Task<User?> GetByIdAsync(string id);
    Task<User?> GetByUsernameAsync(string username);
}
