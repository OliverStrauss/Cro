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
        "#FDD835",
        "#6D4C41",
    ];

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
