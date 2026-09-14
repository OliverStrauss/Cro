using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using CroApp.Api.Models;

namespace CroApp.Api.Services;

// Calls the free public Nominatim (OpenStreetMap) geocoder server-side, never from the
// Flutter client - its usage policy wants a real identifying User-Agent (set on the typed
// HttpClient at registration in Program.cs), which browser JS can't set. Usage policy also
// caps free use at ~1 req/sec; the web shell's search debounce keeps real traffic well
// under that at this app's current scale - see TECH_DEBT.md.
public class NominatimGeocodingService : IGeocodingService
{
    private readonly HttpClient _httpClient;

    public NominatimGeocodingService(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<List<PlaceSearchResult>> SearchAsync(string query)
    {
        var uri = $"search?q={Uri.EscapeDataString(query)}&format=json&limit=5";
        var results = await _httpClient.GetFromJsonAsync<List<NominatimResult>>(uri);
        return (results ?? [])
            .Select(r => new PlaceSearchResult(
                r.DisplayName,
                double.Parse(r.Lat, CultureInfo.InvariantCulture),
                double.Parse(r.Lon, CultureInfo.InvariantCulture)))
            .ToList();
    }

    private record NominatimResult(
        [property: JsonPropertyName("display_name")] string DisplayName,
        [property: JsonPropertyName("lat")] string Lat,
        [property: JsonPropertyName("lon")] string Lon);
}
