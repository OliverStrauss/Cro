namespace CroApp.Api.Services;

// Must stay in sync with app/lib/utils/color_utils.dart's palette - there's no shared
// schema/codegen between the .NET backend and Flutter frontend in this repo, so a change
// here needs a matching manual edit there.
public static class FriendColorPalette
{
    public static readonly string[] Colors =
    [
        "#E53935",
        "#1E88E5",
        "#43A047",
        "#FB8C00",
        "#8E24AA",
        "#00ACC1",
        "#D81B60",
        "#6D4C41",
    ];

    // Every bot shows in this one color (Fog, #6B7280 - also the UI's "no color" fallback), so it
    // reads as "not a person" at a glance. Deliberately NOT in Colors, so bots never use up one of
    // the 8 slots humans get, and a user can't pick it for a human friend.
    public const string BotColor = "#6B7280";

    // Read-time override so friendships accepted before a bot existed/was recolored (already
    // stored with a palette color) still show the bot color.
    public static string? Resolve(string? storedColor, bool isBot) => isBot ? BotColor : storedColor;

    public static string PickFor(bool isBot, IEnumerable<string> existingColors) =>
        isBot ? BotColor : PickNext(existingColors);

    public static string PickNext(IEnumerable<string> existingColors)
    {
        var used = new HashSet<string>(existingColors);
        foreach (var color in Colors)
        {
            if (!used.Contains(color))
            {
                return color;
            }
        }

        // Palette exhausted - wrap around and reuse rather than fail.
        return Colors[used.Count % Colors.Length];
    }
}
