import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:cro_app/models/friend_waypoint.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/utils/color_utils.dart';

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

class _FakeFriendsService implements FriendsService {
  List<FriendWaypoint> friendWaypointsToReturn = [];

  @override
  Future<List<FriendWaypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

void main() {
  testWidgets('shows loading indicator before waypoint loads', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeService, friendsService: _FakeFriendsService()),
    ));

    expect(find.byKey(const Key('mapLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows the waypoint name once loaded', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointToReturn = Waypoint(name: 'Backyard', latitude: 1.0, longitude: 2.0);
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeService, friendsService: _FakeFriendsService()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Delivery spot: Backyard'), findsOneWidget);
  });

  testWidgets('map has a minimum zoom floor and a latitude camera constraint', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointToReturn = Waypoint(name: 'Backyard', latitude: 1.0, longitude: 2.0);
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeService, friendsService: _FakeFriendsService()),
    ));
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.minZoom, 3);
    expect(map.options.cameraConstraint, isA<ContainCameraLatitude>());
  });

  testWidgets('no-waypoint default zoom is not below the configured minZoom', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService()),
    ));
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialZoom, greaterThanOrEqualTo(map.options.minZoom!));
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()..errorToThrow = WaypointException('Could not reach the server');
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeService, friendsService: _FakeFriendsService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mapErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping the map prompts for a name and saves it', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeService, friendsService: _FakeFriendsService()),
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

  testWidgets('renders one marker per friend waypoint plus the own waypoint marker',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointToReturn = Waypoint(name: 'Backyard', latitude: 1.0, longitude: 2.0);
    // Kept close to the own waypoint (1.0, 2.0) so they land inside the initial
    // zoom-13 viewport - flutter_map culls markers whose projected position falls
    // outside the visible pixel bounds, so an out-of-view marker never mounts a widget.
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        FriendWaypoint(userId: 'f1', username: 'alice', color: '#E53935', latitude: 1.001, longitude: 2.001),
        FriendWaypoint(userId: 'f2', username: 'bob', color: '#1E88E5', latitude: 1.002, longitude: 2.002),
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: fakeWaypointService, friendsService: fakeFriendsService),
    ));
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers, hasLength(3));
    expect(find.byKey(const Key('friendMarker_f1')), findsOneWidget);
    expect(find.byKey(const Key('friendMarker_f2')), findsOneWidget);
  });

  testWidgets('tapping a friend marker shows their username in a SnackBar', (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        FriendWaypoint(userId: 'f1', username: 'alice', color: '#E53935', latitude: 1.001, longitude: 2.001),
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: fakeFriendsService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friendMarker_f1')));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('tapping the own waypoint marker shows its details in a dialog', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointToReturn = Waypoint(name: 'Backyard', latitude: 1.0, longitude: 2.0);
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownWaypointMarker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypointDetailsDialog')), findsOneWidget);
    expect(find.text('Latitude: 1.0'), findsOneWidget);
    expect(find.text('Longitude: 2.0'), findsOneWidget);
  });

  testWidgets('refresh() reloads data - needed since IndexedStack never rebuilds this screen',
      (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        FriendWaypoint(userId: 'f1', username: 'alice', color: '#E53935', latitude: 1.0, longitude: 2.0),
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState, waypointService: _FakeWaypointService(), friendsService: fakeFriendsService),
    ));
    await tester.pumpAndSettle();

    // Simulate a color change that happened elsewhere in the app while this screen sat
    // alive but unbuilt in the IndexedStack.
    fakeFriendsService.friendWaypointsToReturn = [
      FriendWaypoint(userId: 'f1', username: 'alice', color: '#1E88E5', latitude: 1.0, longitude: 2.0),
    ];

    await tester.state<MapScreenState>(find.byType(MapScreen)).refresh();
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final friendMarker = markerLayer.markers.firstWhere((m) => m.key == const Key('friendMarker_f1'));
    final icon = (friendMarker.child as GestureDetector).child as Icon;
    expect(icon.color, hexToColor('#1E88E5'));
  });
}
