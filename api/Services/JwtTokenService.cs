using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using CroApp.Api.Data;
using Microsoft.IdentityModel.Tokens;
using User = CroApp.Api.Models.User;

namespace CroApp.Api.Services;

public static class JwtTokenService
{
    public static (string Token, DateTimeOffset ExpiresAt) GenerateToken(User user, JwtOptions options)
    {
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(options.ExpiryMinutes);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id),
            new Claim(JwtRegisteredClaimNames.UniqueName, user.Username)
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: options.Issuer,
            audience: options.Audience,
            claims: claims,
            expires: expiresAt.UtcDateTime,
            signingCredentials: credentials);

        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }
}
