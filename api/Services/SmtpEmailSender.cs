using System.Net;
using System.Net.Mail;
using CroApp.Api.Data;
using Microsoft.Extensions.Options;

namespace CroApp.Api.Services;

// Real email delivery via plain SMTP (System.Net.Mail - built into the BCL, no extra
// dependency needed for a single plaintext message). Only registered when Smtp:Host is
// configured - see Program.cs - so this never runs against unset credentials.
public class SmtpEmailSender : IEmailSender
{
    private readonly SmtpOptions _options;

    public SmtpEmailSender(IOptions<SmtpOptions> options)
    {
        _options = options.Value;
    }

    public async Task SendPasswordResetCodeAsync(string toEmail, string code)
    {
        using var client = new SmtpClient(_options.Host, _options.Port)
        {
            Credentials = new NetworkCredential(_options.Username, _options.Password),
            EnableSsl = true,
        };
        using var message = new MailMessage(_options.FromAddress, toEmail)
        {
            Subject = "Reset your Cro password",
            Body = $"Your password reset code is {code}. It expires in 15 minutes.",
        };
        await client.SendMailAsync(message);
    }
}
