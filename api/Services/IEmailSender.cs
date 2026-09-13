namespace CroApp.Api.Services;

public interface IEmailSender
{
    Task SendPasswordResetCodeAsync(string toEmail, string code);
    Task SendEmailVerificationCodeAsync(string toEmail, string code);
}
