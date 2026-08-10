namespace CroApp.Api.Services;

// Placeholder species roster for the send/travel mechanic. Base speeds are tunable game-
// pacing numbers (km/h, as if flown continuously) chosen so that a few-hundred-km journey
// takes hours and a multi-thousand-km one takes multiple physical days at the default
// BirdTravelOptions.SpeedMultiplier of 1.0 - not real bird biology, not precision-critical,
// safe to retune later.
public static class BirdTypeCatalog
{
    public static readonly (string Name, double BaseSpeedKmh)[] Types =
    [
        ("Sparrow", 20.0),
        ("Pigeon", 35.0),
        ("Falcon", 60.0),
    ];

    // Deterministic by creation-slot index (0-based) - same "no randomness" preference as
    // FriendColorPalette.PickNext. Wraps around via modulo if BirdsPerUser ever exceeds
    // Types.Length.
    public static string PickForSlot(int slotIndex) => Types[slotIndex % Types.Length].Name;

    public static double BaseSpeedKmh(string type)
    {
        foreach (var candidate in Types)
        {
            if (candidate.Name == type)
            {
                return candidate.BaseSpeedKmh;
            }
        }

        // Unrecognized/legacy type value - fall back to the slowest rather than throw.
        return Types[0].BaseSpeedKmh;
    }
}
