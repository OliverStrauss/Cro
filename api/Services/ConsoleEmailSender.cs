namespace CroApp.Api.Services;

// Dev-only fallback when Acs:ConnectionString isn't configured - same category as the other
// dev-only shortcuts in CLAUDE.md (fixed emulator keys, etc). Logs the code instead of
// emailing it, so the reset/verification flows are exercisable locally without real ACS
// credentials.
public class ConsoleEmailSender : IEmailSender
{
    private readonly ILogger<ConsoleEmailSender> _logger;

    public ConsoleEmailSender(ILogger<ConsoleEmailSender> logger)
    {
        _logger = logger;
    }

    public Task SendPasswordResetCodeAsync(string toEmail, string code)
    {
        _logger.LogInformation("[dev email] Password reset code for {Email}: {Code}", toEmail, code);
        return Task.CompletedTask;
    }

    public Task SendEmailVerificationCodeAsync(string toEmail, string code)
    {
        _logger.LogInformation("[dev email] Email verification code for {Email}: {Code}", toEmail, code);
        return Task.CompletedTask;
    }
}
