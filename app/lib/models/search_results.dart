import 'hub.dart';
import 'place_search_result.dart';
import 'waypoint.dart';

// The full response shape of GET /search - sectioned exactly the way the search dropdown
// renders it (Places / Hubs / Nests), so no client-side grouping logic is needed.
class SearchResults {
  final List<PlaceSearchResult> places;
  final List<Hub> hubs;
  final List<Waypoint> nests;

  SearchResults({required this.places, required this.hubs, required this.nests});

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        places: (json['places'] as List<dynamic>)
            .map((e) => PlaceSearchResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        hubs: (json['hubs'] as List<dynamic>).map((e) => Hub.fromJson(e as Map<String, dynamic>)).toList(),
        nests: (json['nests'] as List<dynamic>).map((e) => Waypoint.fromJson(e as Map<String, dynamic>)).toList(),
      );

  bool get isEmpty => places.isEmpty && hubs.isEmpty && nests.isEmpty;
}
