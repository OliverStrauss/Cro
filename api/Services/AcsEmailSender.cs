using Azure.Communication.Email;
using CroApp.Api.Data;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// Sends via Azure Communication Services' Email API (HTTPS, port 443) - not SMTP, since
// Azure App Service's shared/Basic plans block outbound SMTP (25/587) at the platform level
// for anti-spam reasons, so a System.Net.Mail/SmtpClient sender can never deliver from there
// regardless of credentials. Uses the official SDK rather than hand-rolling the REST API's
// HMAC request signing. Only registered when Acs:ConnectionString is configured - see
// Program.cs.
public class AcsEmailSender : IEmailSender
{
    private readonly EmailClient _client;
    private readonly string _fromAddress;

    public AcsEmailSender(IOptions<AcsEmailOptions> options)
    {
        _client = new EmailClient(options.Value.ConnectionString);
        _fromAddress = options.Value.FromAddress;
    }

    public Task SendPasswordResetCodeAsync(string toEmail, string code) =>
        SendAsync(toEmail, "Reset your Cro password", $"Your password reset code is {code}. It expires in 15 minutes.");

    public Task SendEmailVerificationCodeAsync(string toEmail, string code) =>
        SendAsync(toEmail, "Verify your Cro email", $"Your email verification code is {code}. It expires in 24 hours.");

    private async Task SendAsync(string toEmail, string subject, string plainTextBody)
    {
        var message = new EmailMessage(_fromAddress, toEmail, new EmailContent(subject) { PlainText = plainTextBody });
        await _client.SendAsync(Azure.WaitUntil.Completed, message);
    }
}
