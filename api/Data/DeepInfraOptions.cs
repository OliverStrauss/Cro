namespace CroApp.Api.Data;

// DeepInfra's OpenAI-compatible chat-completions endpoint hosts open-weight models (Llama,
// Mistral, etc.) at a fraction of a hosted frontier model's per-token price - see
// TECH_DEBT.md for why that tradeoff was accepted for bot flavor text specifically. Same
// "empty means not configured" shape as AcsEmailOptions: BotOrchestratorService is only
// registered as a hosted service (see Program.cs) when ApiKey is non-empty, so an
// unconfigured environment (every test fixture, a fresh local checkout) simply never spins
// up the tick loop rather than failing on every attempted call.
public class DeepInfraOptions
{
    public string ApiKey { get; set; } = string.Empty;
    public string BaseUrl { get; set; } = "https://api.deepinfra.com/v1/openai/";
    public string DefaultModel { get; set; } = "meta-llama/Meta-Llama-3.1-8B-Instruct";
}
