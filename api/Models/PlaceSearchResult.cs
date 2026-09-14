namespace CroApp.Api.Models;

// One geocoded real-world address/business hit from IGeocodingService, for the unified
// /search endpoint - deliberately not backed by a Cosmos container, unlike Hub/Waypoint,
// since it's never stored, only ever a passthrough of a third-party geocoder's response.
public record PlaceSearchResult(string DisplayName, double Latitude, double Longitude);
