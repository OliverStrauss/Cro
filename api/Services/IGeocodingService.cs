using CroApp.Api.Models;

namespace CroApp.Api.Services;

// Exists as an interface only so tests can swap in a fake instead of hitting a real
// geocoder over the network (see SearchEndpointTests.FakeGeocodingService) - not for any
// planned second provider.
public interface IGeocodingService
{
    Task<List<PlaceSearchResult>> SearchAsync(string query);
}
