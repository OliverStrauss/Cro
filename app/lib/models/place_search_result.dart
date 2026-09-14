// A geocoded real-world address/business hit from GET /search's "places" section - not
// backed by any local id, unlike a Hub/Waypoint search hit, since there's no app entity to
// look up afterward (see SearchTrigger's onSelectPlace).
class PlaceSearchResult {
  final String displayName;
  final double latitude;
  final double longitude;

  PlaceSearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) => PlaceSearchResult(
        displayName: json['displayName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
