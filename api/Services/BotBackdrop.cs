using CroApp.Api.Models;

namespace CroApp.Api.Services;

// The "world" a bot is told about on top of its persona and the one message it's answering:
// what time it is where it lives, how long/far a cro travelled, how many cros it has traded
// with this friend, the last few lines of that conversation, and (for a Hub post) the board's
// latest posts. All of it is gathered in plain C# by BotOrchestratorService and formatted here,
// so the LLM call stays one small prompt and none of this needs an extra model round trip.
public record BotBackdrop(
    string LocalTime,
    int ExchangeCount,
    string? TravelNote,
    IReadOnlyList<BotThreadLine> History,
    IReadOnlyList<string> BoardTail);

// Pure helpers (no clock, no I/O) so they're unit-testable without the emulator.
public static class BotBackdropFacts
{
    public const int MaxThreadLines = 6;
    public const int BoardTailSize = 4;

    // Cheap solar-time approximation (longitude / 15 = hours from UTC) rather than a tz
    // database lookup - only feeds a "Sunday evening" flavor line, and nests carry no timezone.
    public static string LocalTime(DateTimeOffset utcNow, double longitude)
    {
        var local = utcNow.UtcDateTime.AddHours(longitude / 15.0);
        var part = local.Hour switch { >= 5 and < 12 => "morning", >= 12 and < 17 => "afternoon", >= 17 and < 22 => "evening", _ => "night" };
        return $"{local.DayOfWeek} {part}";
    }

    public static string Duration(TimeSpan span) => span.TotalHours switch
    {
        < 1 => "under an hour",
        < 48 => Plural((int)Math.Round(span.TotalHours), "hour"),
        _ => Plural((int)Math.Round(span.TotalDays), "day"),
    };

    public static string Distance(double km) => km < 1 ? "under a kilometer" : $"about {Math.Round(km)} km";

    // What the bot is told about an inbound cro's journey; null when nothing is known.
    public static string? ReplyNote(string sender, double? km, TimeSpan? took)
    {
        var bits = new List<string>();
        if (took is { } t) bits.Add($"took {Duration(t)} to arrive");
        if (km is { } d) bits.Add($"travelled {Distance(d)}");
        return bits.Count == 0 ? null : $"{sender}'s message {string.Join(" and ", bits)}.";
    }

    public static string? OutboundNote(string target, double? km) =>
        km is { } d ? $"{target} is {Distance(d)} from your nest, so your message will take a while to arrive." : null;

    // Appends to a bot's per-friend log, keeping only the newest MaxThreadLines so a BotProfile
    // document stays small however long a friendship runs.
    public static List<BotThreadLine> AppendThread(IEnumerable<BotThreadLine>? existing, IEnumerable<BotThreadLine> added) =>
        (existing ?? []).Concat(added).TakeLast(MaxThreadLines).ToList();

    private static string Plural(int n, string unit) => n == 1 ? $"about 1 {unit}" : $"about {n} {unit}s";
}
