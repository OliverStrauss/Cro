using System.Net.Http.Headers;
using System.Net.Http.Json;
using CroApp.Api.Data;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// Sends via SendGrid's HTTPS API (port 443), not SMTP - Azure App Service's shared/Basic
// plans block outbound SMTP (25/587) at the platform level for anti-spam reasons, so a
// System.Net.Mail/SmtpClient sender can never deliver from there regardless of credentials.
// Only registered when SendGrid:ApiKey is configured - see Program.cs.
public class SendGridEmailSender : IEmailSender
{
    private readonly HttpClient _httpClient;
    private readonly SendGridOptions _options;

    public SendGridEmailSender(HttpClient httpClient, IOptions<SendGridOptions> options)
    {
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri("https://api.sendgrid.com/");
        _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", options.Value.ApiKey);
        _options = options.Value;
    }

    public async Task SendPasswordResetCodeAsync(string toEmail, string code)
    {
        var response = await _httpClient.PostAsJsonAsync("v3/mail/send", new
        {
            personalizations = new[] { new { to = new[] { new { email = toEmail } } } },
            from = new { email = _options.FromAddress },
            subject = "Reset your Cro password",
            content = new[]
            {
                new { type = "text/plain", value = $"Your password reset code is {code}. It expires in 15 minutes." }
            }
        });
        response.EnsureSuccessStatusCode();
    }
}
