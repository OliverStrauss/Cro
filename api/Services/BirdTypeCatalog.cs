namespace CroApp.Api.Services;

// The four bird types a user can compose, each with a distinct required payload (see
// BirdPayloadValidator) and speed tier. Base speeds are tunable game-pacing numbers (km/h,
// as if flown continuously) chosen so that a few-hundred-km journey takes hours and a
// multi-thousand-km one takes multiple physical days at the default
// BirdTravelOptions.SpeedMultiplier of 1.0 - not real bird biology, not precision-critical,
// safe to retune later. This is a full replacement of the old placeholder species roster
// (Sparrow/Pigeon/Falcon) rather than a rename - the old roster's "Pigeon" was a different
// (mid) speed tier than this one's (slowest), so keeping old bird documents' Type values
// around unmapped would be ambiguous; there's no migration path for pre-existing values.
public static class BirdTypeCatalog
{
    public const string Cro = "Cro";
    public const string Parrot = "Parrot";
    public const string Raven = "Raven";
    public const string Pigeon = "Pigeon";

    public static readonly (string Name, double BaseSpeedKmh)[] Types =
    [
        (Cro, 60.0),
        (Parrot, 40.0),
        (Raven, 25.0),
        (Pigeon, 15.0),
    ];

    public static bool IsValid(string type) => Types.Any(t => t.Name == type);

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
        return Types[^1].BaseSpeedKmh;
    }
}
