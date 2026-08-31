namespace CroApp.Api.Services;

// The fixed set of category labels a Hub can be tagged with when placed or suggested,
// replacing what used to be a free-text field on Hub.Category. Closed like
// BirdTypeCatalog (a bounded, UI-driven picker) rather than open-ended like HubStatus (a
// state machine) - see Hub.cs. "Other" is the default when a suggester doesn't have a
// better fit, so it's always a valid fallback rather than an escape hatch for bad data.
public static class HubCategoryCatalog
{
    public const string Housing = "Housing";
    public const string IowaState = "Iowa State";
    public const string Bar = "Bar";
    public const string Park = "Park";
    public const string Business = "Business";
    public const string Landmark = "Landmark";
    public const string Other = "Other";

    public static readonly string[] All =
    [
        Housing,
        IowaState,
        Bar,
        Park,
        Business,
        Landmark,
        Other,
    ];

    public static bool IsValid(string category) => All.Contains(category);
}
