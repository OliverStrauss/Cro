import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/place_search_result.dart';
import 'package:cro_app/models/search_results.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/search_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/widgets/search_trigger.dart';

class _FakeSearchService implements SearchService {
  SearchResults results = SearchResults(places: [], hubs: [], nests: []);
  String? lastQuery;

  @override
  Future<SearchResults> search(String token, String query) async {
    lastQuery = query;
    return results;
  }
}

void main() {
  late _FakeSearchService searchService;
  late AuthState authState;
  PlaceSearchResult? selectedPlace;
  Hub? selectedHub;
  Waypoint? selectedNest;

  setUp(() {
    searchService = _FakeSearchService();
    authState = AuthState()..login('a.b.c');
    selectedPlace = null;
    selectedHub = null;
    selectedNest = null;
  });

  Widget build() {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SearchTrigger(
            searchService: searchService,
            authState: authState,
            onSelectPlace: (p) => selectedPlace = p,
            onSelectHub: (h) => selectedHub = h,
            onSelectNest: (n) => selectedNest = n,
          ),
        ),
      ),
    );
  }

  testWidgets('opens a search field when the trigger is tapped', (tester) async {
    await tester.pumpWidget(build());

    expect(find.byKey(const Key('webSearchField')), findsNothing);

    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webSearchField')), findsOneWidget);
  });

  testWidgets('typing debounces then shows sectioned results from the search service', (tester) async {
    searchService.results = SearchResults(
      places: [PlaceSearchResult(displayName: 'Ames, Iowa, USA', latitude: 42.03, longitude: -93.63)],
      hubs: [Hub(id: 'hub1', name: 'Ames Cafe', latitude: 42.0, longitude: -93.6, status: 'Approved', createdByUserId: 'u1')],
      nests: [Waypoint(id: 'nest1', userId: 'u2', name: 'Ames Library', latitude: 42.0, longitude: -93.6)],
    );

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('webSearchField')), 'Ames');
    // Debounce is 250ms, matching web_profile_screen.dart's friend search.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(searchService.lastQuery, 'Ames');
    expect(find.text('Ames, Iowa, USA'), findsOneWidget);
    expect(find.text('Ames Cafe'), findsOneWidget);
    expect(find.text('Ames Library'), findsOneWidget);
  });

  testWidgets('selecting a hub result calls onSelectHub with that hub', (tester) async {
    final hub = Hub(id: 'hub1', name: 'Ames Cafe', latitude: 42.0, longitude: -93.6, status: 'Approved', createdByUserId: 'u1');
    searchService.results = SearchResults(places: [], hubs: [hub], nests: []);

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('webSearchField')), 'Ames');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('webSearchResultHub_${hub.id}')));
    await tester.pumpAndSettle();

    expect(selectedHub?.id, hub.id);
  });

  testWidgets('selecting a nest result calls onSelectNest with that nest', (tester) async {
    final nest = Waypoint(id: 'nest1', userId: 'u2', name: 'Ames Library', latitude: 42.0, longitude: -93.6);
    searchService.results = SearchResults(places: [], hubs: [], nests: [nest]);

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('webSearchField')), 'Ames');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('webSearchResultNest_${nest.id}')));
    await tester.pumpAndSettle();

    expect(selectedNest?.id, nest.id);
  });

  testWidgets('selecting a place result calls onSelectPlace with that place', (tester) async {
    final place = PlaceSearchResult(displayName: 'Ames, Iowa, USA', latitude: 42.03, longitude: -93.63);
    searchService.results = SearchResults(places: [place], hubs: [], nests: []);

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('webSearchField')), 'Ames');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webSearchResultPlace_0')));
    await tester.pumpAndSettle();

    expect(selectedPlace?.displayName, place.displayName);
  });

  testWidgets('an empty query shows no results section', (tester) async {
    await tester.pumpWidget(build());
    await tester.tap(find.byKey(const Key('webSearchTrigger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webSearchResults')), findsNothing);
  });
}
