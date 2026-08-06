import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';

class _FakeWaypointService implements WaypointService {
  Waypoint? waypointToReturn;
  Object? errorToThrow;
  Waypoint? savedWaypoint;

  @override
  Future<Waypoint?> getWaypoint(String token) async {
    if (errorToThrow != null) throw errorToThrow!;
    return waypointToReturn;
  }

  @override
  Future<Waypoint> saveWaypoint(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final saved = Waypoint(name: name, latitude: latitude, longitude: longitude);
    savedWaypoint = saved;
    return saved;
  }
}

void main() {
  testWidgets('shows loading indicator before waypoint loads', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(authState: authState, waypointService: fakeService),
    ));

    expect(find.byKey(const Key('mapLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows the waypoint name once loaded', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointToReturn = Waypoint(name: 'Backyard', latitude: 1.0, longitude: 2.0);
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Delivery spot: Backyard'), findsOneWidget);
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()..errorToThrow = WaypointException('Could not reach the server');
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mapErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping the map prompts for a name and saves it', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    // flutter_map's internal gesture recognizer doesn't reliably fire from a synthetic
    // tester.tap() in the widget test harness - call the tap handler directly instead.
    // Everything downstream (the real dialog, real save call) is still exercised for real.
    tester.state<MapScreenState>(find.byType(MapScreen)).handleMapTap(const LatLng(1, 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypointNameField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('waypointNameField')), 'Front Porch');
    await tester.tap(find.byKey(const Key('saveWaypointButton')));
    await tester.pumpAndSettle();

    expect(fakeService.savedWaypoint?.name, 'Front Porch');
  });
}
