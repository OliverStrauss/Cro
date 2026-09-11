using System.Net;
using System.Net.Http.Json;
using CroApp.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace CroApp.Api.Tests;

public class PasswordResetEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly FakeEmailSender _emailSender = new();

    public PasswordResetEndpointTests(WebApplicationFactory<Program> factory)
    {
        var connectionString = TestConfig.ResolveCosmosConnectionString();

        var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(TestConfig.Build(cosmosConnectionString: connectionString));
            });
            // Overrides Program.cs's ConsoleEmailSender fallback so the test can read the
            // code that would otherwise only go to a log line - last registration for a
            // service type wins on resolution, so this replaces it without needing Replace().
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
    public async Task ForgotPassword_WithKnownEmail_SendsCode()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"reset-user-{Guid.NewGuid():N}", email, "original-password");

        var response = await _client.PostAsJsonAsync("/forgot-password", new { Email = email });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(email, _emailSender.LastEmail);
        Assert.NotNull(_emailSender.LastCode);
        Assert.Equal(6, _emailSender.LastCode!.Length);
    }

    [Fact]
    public async Task ForgotPassword_WithUnknownEmail_StillReturnsOkAndSendsNothing()
    {
        var response = await _client.PostAsJsonAsync("/forgot-password", new { Email = $"nobody-{Guid.NewGuid():N}@example.com" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(_emailSender.LastCode);
    }

    [Fact]
    public async Task ResetPassword_WithCorrectCode_ChangesPasswordAndAllowsLogin()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        var username = $"reset-user-{Guid.NewGuid():N}";
        await RegisterUserAsync(username, email, "original-password");
        await _client.PostAsJsonAsync("/forgot-password", new { Email = email });
        var code = _emailSender.LastCode!;

        var resetResponse = await _client.PostAsJsonAsync("/reset-password", new { Email = email, Code = code, NewPassword = "brand-new-password" });
        Assert.Equal(HttpStatusCode.OK, resetResponse.StatusCode);

        var loginResponse = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "brand-new-password" });
        Assert.Equal(HttpStatusCode.OK, loginResponse.StatusCode);

        var oldPasswordLogin = await _client.PostAsJsonAsync("/login", new { Username = username, Password = "original-password" });
        Assert.Equal(HttpStatusCode.Unauthorized, oldPasswordLogin.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_WithWrongCode_ReturnsBadRequest()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"reset-user-{Guid.NewGuid():N}", email, "original-password");
        await _client.PostAsJsonAsync("/forgot-password", new { Email = email });

        var resetResponse = await _client.PostAsJsonAsync("/reset-password", new { Email = email, Code = "000000", NewPassword = "brand-new-password" });

        Assert.Equal(HttpStatusCode.BadRequest, resetResponse.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_WithoutRequestingCodeFirst_ReturnsBadRequest()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterUserAsync($"reset-user-{Guid.NewGuid():N}", email, "original-password");

        var resetResponse = await _client.PostAsJsonAsync("/reset-password", new { Email = email, Code = "123456", NewPassword = "brand-new-password" });

        Assert.Equal(HttpStatusCode.BadRequest, resetResponse.StatusCode);
    }

    private class FakeEmailSender : IEmailSender
    {
        public string? LastEmail { get; private set; }
        public string? LastCode { get; private set; }

        public Task SendPasswordResetCodeAsync(string toEmail, string code)
        {
            LastEmail = toEmail;
            LastCode = code;
            return Task.CompletedTask;
        }
    }
}
