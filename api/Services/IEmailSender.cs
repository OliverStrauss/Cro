namespace CroApp.Api.Services;

public interface IEmailSender
{
    Task SendPasswordResetCodeAsync(string toEmail, string code);
}
