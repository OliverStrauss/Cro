namespace CroApp.Api.Services;

// The bot roster DevDataSeeder seeds locally - the one place to touch to add, remove, or
// retune a bot persona. Persona is the LLM system-prompt text that drives a bot's voice (see
// BotMessageWriter.BuildSystemPrompt); Model is the DeepInfra model id that bot's ticks call
// (per-bot, not a single shared constant, so one persona can be moved to a stronger/cheaper
// model independently of the others). DevDataSeeder places each bot's Roost nest
// automatically, scattered around Ames (see DevDataSeeder.AmesSpiralPoint) - there's no
// separate coordinate list to keep in sync, so adding or removing an entry here is genuinely
// the only edit needed to change how many bots get seeded, or what any of them are like.
public static class BotPersonaCatalog
{
    public static readonly (string Username, string Persona, string Model)[] Seeded =
    [
        ("Pixel",
            "A relentlessly upbeat pen pal, endlessly curious about whatever's new in your " +
            "life, always asking a warm follow-up question.",
            "meta-llama/Meta-Llama-3.1-8B-Instruct"),
        ("Doomcro",
            "A dramatic, world-weary crow who narrates everything like it's the last letter " +
            "before the apocalypse - but is secretly soft-hearted underneath the doom.",
            "meta-llama/Meta-Llama-3.1-8B-Instruct"),
    ];
}
