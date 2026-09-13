using System.Net;
using System.Net.Http.Json;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace CroApp.Api.Tests;

public class EmailVerificationEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly FakeEmailSender _emailSender = new();

    public EmailVerificationEndpointTests(WebApplicationFactory<Program> factory)
    {
        var connectionString = TestConfig.ResolveCosmosConnectionString();

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build(cosmosConnectionString: connectionString));
                // Overrides TestConfig.Build()'s default "false" - this class is the one place
                // that specifically exercises the verification-required behavior itself.
                config.AddInMemoryCollection(new Dictionary<string, string?> { ["Auth:RequireEmailVerification"] = "true" });
            });
            builder.ConfigureTestServices(services => services.AddSingleton<IEmailSender>(_emailSender));
        });

        _client = configuredFactory.CreateClient();
    }

    private async Task<string> RegisterUserAsync(string username, string email, string password)
    {
        var createResponse = await _client.PostAsJsonAsync("/users", new { Username = username, Email = email, Password = password });
        createResponse.EnsureSuccessStatusCode();
        return username;
    }

    [Fact]
    public async Task CreateUser_SendsVerificationCode()
    {
        var email = $"verify-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"verify-user-{Guid.NewGuid():N}", email, "correct-horse-battery-staple");

        Assert.Equal(email, _emailSender.LastVerificationEmail);
        Assert.NotNull(_emailSender.LastVerificationCode);
        Assert.Equal(6, _emailSender.LastVerificationCode!.Length);
    }

    [Fact]
    public async Task Login_BeforeVerifying_ReturnsForbidden()
    {
        var email = $"verify-{Guid.NewGuid():N}@example.com";
        var username = $"verify-user-{Guid.NewGuid():N}";
        await RegisterUserAsync(username, email, "correct-horse-battery-staple");

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "correct-horse-battery-staple" });

        Assert.Equal(HttpStatusCode.Forbidden, loginResponse.StatusCode);
    }

    [Fact]
    public async Task VerifyEmail_WithCorrectCode_AllowsLogin()
    {
        var email = $"verify-{Guid.NewGuid():N}@example.com";
        var username = $"verify-user-{Guid.NewGuid():N}";
        await RegisterUserAsync(username, email, "correct-horse-battery-staple");
        var code = _emailSender.LastVerificationCode!;

        var verifyResponse = await _client.PostAsJsonAsync("/verify-email", new { Email = email, Code = code });
        Assert.Equal(HttpStatusCode.OK, verifyResponse.StatusCode);

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "correct-horse-battery-staple" });
        Assert.Equal(HttpStatusCode.OK, loginResponse.StatusCode);
    }

    [Fact]
    public async Task VerifyEmail_WithWrongCode_ReturnsBadRequest()
    {
        var email = $"verify-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"verify-user-{Guid.NewGuid():N}", email, "correct-horse-battery-staple");

        var verifyResponse = await _client.PostAsJsonAsync("/verify-email", new { Email = email, Code = "000000" });

        Assert.Equal(HttpStatusCode.BadRequest, verifyResponse.StatusCode);
    }

    [Fact]
    public async Task ResendVerificationEmail_ForUnverifiedAccount_SendsNewCode()
    {
        var email = $"verify-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"verify-user-{Guid.NewGuid():N}", email, "correct-horse-battery-staple");
        var firstCode = _emailSender.LastVerificationCode!;

        var resendResponse = await _client.PostAsJsonAsync("/resend-verification-email", new { Email = email });
        Assert.Equal(HttpStatusCode.OK, resendResponse.StatusCode);

        Assert.NotNull(_emailSender.LastVerificationCode);
        var verifyResponse = await _client.PostAsJsonAsync("/verify-email", new { Email = email, Code = _emailSender.LastVerificationCode! });
        Assert.Equal(HttpStatusCode.OK, verifyResponse.StatusCode);
        // The original code should no longer work once a fresh one has been issued and used
        // (EmailVerificationCodeHash is cleared on successful verification either way, but this
        // also guards against the resend having silently kept the old hash).
        Assert.NotEqual(firstCode, _emailSender.LastVerificationCode);
    }

    [Fact]
    public async Task ResendVerificationEmail_ForUnknownEmail_StillReturnsOkAndSendsNothing()
    {
        var response = await _client.PostAsJsonAsync("/resend-verification-email", new { Email = $"nobody-{Guid.NewGuid():N}@example.com" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(_emailSender.LastVerificationCode);
    }

    private class FakeEmailSender : IEmailSender
    {
        public string? LastVerificationEmail { get; private set; }
        public string? LastVerificationCode { get; private set; }

        public Task SendPasswordResetCodeAsync(string toEmail, string code) => Task.CompletedTask;

        public Task SendEmailVerificationCodeAsync(string toEmail, string code)
        {
            LastVerificationEmail = toEmail;
            LastVerificationCode = code;
            return Task.CompletedTask;
        }
    }
}
