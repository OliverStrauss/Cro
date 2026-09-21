using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace CroApp.Api.Services;

// Thin wrapper around DeepInfra's OpenAI-compatible /chat/completions endpoint - the same
// server-side-only-HTTP-call shape as NominatimGeocodingService (BaseAddress + auth header
// set once at typed-HttpClient registration in Program.cs, see the AddHttpClient call).
// Returns the assistant's raw text; BotMessageWriter owns cleaning it up, not this class -
// this class only knows how to talk to DeepInfra.
public class DeepInfraChatClient(HttpClient httpClient, ILogger<DeepInfraChatClient> logger)
{
    // Caps max_tokens - a bot's reply is a short chat message, not an essay, and an unbounded
    // completion would be pure wasted spend for no product benefit
    // (BotOrchestratorOptions.MaxReplyContentLength trims further on the way in, but that's a
    // defensive backstop, not the primary cost control).
    private const int MaxTokens = 120;
    private const double Temperature = 0.9;

    public async Task<string?> CompleteAsync(string model, string systemPrompt, string userPrompt, CancellationToken cancellationToken)
    {
        var request = new ChatCompletionRequest(
            model,
            [
                new ChatMessage("system", systemPrompt),
                new ChatMessage("user", userPrompt),
            ],
            MaxTokens,
            Temperature);

        using var response = await httpClient.PostAsJsonAsync("chat/completions", request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            logger.LogWarning("BOT_LLM DeepInfra chat completion failed ({StatusCode}): {Body}", (int)response.StatusCode, body);
            return null;
        }

        var completion = await response.Content.ReadFromJsonAsync<ChatCompletionResponse>(cancellationToken);
        return completion?.Choices.FirstOrDefault()?.Message.Content;
    }

    // Every property below is explicitly named - unlike this app's own Cosmos/API-response
    // records (which get camelCase for free from CosmosSerializationOptions/ASP.NET Core's web
    // defaults respectively), a raw HttpClient.PostAsJsonAsync call has no such policy applied
    // on the way out, so an un-annotated PascalCase property would serialize as "Model" instead
    // of the "model" DeepInfra's OpenAI-compatible endpoint actually expects. Deserializing the
    // response back doesn't need the same care (System.Net.Http.Json's read path matches
    // property names case-insensitively by default), but every field is annotated anyway for
    // one consistent, unambiguous wire contract in both directions.
    private record ChatCompletionRequest(
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("messages")] List<ChatMessage> Messages,
        [property: JsonPropertyName("max_tokens")] int MaxTokens,
        [property: JsonPropertyName("temperature")] double Temperature);

    private record ChatMessage(
        [property: JsonPropertyName("role")] string Role,
        [property: JsonPropertyName("content")] string Content);

    private record ChatCompletionResponse([property: JsonPropertyName("choices")] List<ChatCompletionChoice> Choices);

    private record ChatCompletionChoice([property: JsonPropertyName("message")] ChatMessage Message);
}
