import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/utils/color_utils.dart';

class _FakeWaypointService implements WaypointService {
  List<Waypoint> waypointsToReturn = [];
  Object? errorToThrow;
  Waypoint? lastCreatedWaypoint;
  int _nextId = 1;

  @override
  Future<List<Waypoint>> listWaypoints(String token) async {
    if (errorToThrow != null) throw errorToThrow!;
    return waypointsToReturn;
  }

  @override
  Future<Waypoint> createWaypoint(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final created =
        Waypoint(id: 'new-${_nextId++}', userId: 'u1', name: name, latitude: latitude, longitude: longitude);
    lastCreatedWaypoint = created;
    return created;
  }

  @override
  Future<Waypoint> updateWaypoint(
    String token,
    String id, {
    required String name,
    required double latitude,
    required double longitude,
  }) async =>
      Waypoint(id: id, userId: 'u1', name: name, latitude: latitude, longitude: longitude);

  @override
  Future<void> deleteWaypoint(String token, String id) async {}
}

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendWaypointsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

class _FakeProfileService implements ProfileService {
  UserProfile? profileToReturn = UserProfile(id: 'u1', username: 'me', email: 'me@example.com');

  @override
  Future<UserProfile> getUser(String userId) async {
    if (profileToReturn == null) throw ProfileException('not found');
    return profileToReturn!;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

// A syntactically valid (unsigned) JWT with the given subject - MapScreen decodes this
// client-side to know which user id to fetch its own profile for.
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({
        'alg': 'HS256'
      })}.${segment({
        'sub': userId
      })}.sig';
}

void main() {
  testWidgets('shows loading indicator before nests load', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));

    expect(find.byKey(const Key('mapLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows the own nest marker once loaded', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ownNestMarker_w1')), findsOneWidget);
  });

  testWidgets('renders a marker per own nest when there are several', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Work', latitude: 1.001, longitude: 2.001),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ownNestMarker_w1')), findsOneWidget);
    expect(find.byKey(const Key('ownNestMarker_w2')), findsOneWidget);
  });

  testWidgets('map has a minimum zoom floor and a latitude camera constraint', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.minZoom, 3);
    expect(map.options.cameraConstraint, isA<ContainCameraLatitude>());
  });

  testWidgets('no-nest default zoom is not below the configured minZoom', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialZoom, greaterThanOrEqualTo(map.options.minZoom!));
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()..errorToThrow = WaypointException('Could not reach the server');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mapErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping the map prompts for a name and creates a nest', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
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

    expect(fakeService.lastCreatedWaypoint?.name, 'Front Porch');
  });

  testWidgets('tapping the map to add a nest keeps existing own nests', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    // Kept close to the existing own nest (1.0, 2.0) - flutter_map culls markers whose
    // projected position falls outside the initial zoom-13 viewport.
    tester.state<MapScreenState>(find.byType(MapScreen)).handleMapTap(const LatLng(1.003, 2.003));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypointNameField')), 'Work');
    await tester.tap(find.byKey(const Key('saveWaypointButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ownNestMarker_w1')), findsOneWidget);
    expect(find.byKey(Key('ownNestMarker_${fakeService.lastCreatedWaypoint!.id}')), findsOneWidget);
  });

  testWidgets('renders one marker per friend waypoint plus the own nest marker',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    // Kept close to the own nest (1.0, 2.0) so they land inside the initial zoom-13
    // viewport - flutter_map culls markers whose projected position falls outside the
    // visible pixel bounds, so an out-of-view marker never mounts a widget.
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            name: "Alice's Yard",
            userId: 'f1',
            username: 'alice',
            color: '#E53935',
            latitude: 1.001,
            longitude: 2.001),
        Waypoint(
            id: 'fw2',
            name: "Bob's Porch",
            userId: 'f2',
            username: 'bob',
            color: '#1E88E5',
            latitude: 1.002,
            longitude: 2.002),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers, hasLength(3));
    expect(find.byKey(const Key('friendMarker_fw1')), findsOneWidget);
    expect(find.byKey(const Key('friendMarker_fw2')), findsOneWidget);
  });

  testWidgets('renders a marker per nest when a friend has several nests', (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            name: "Alice's Home",
            userId: 'f1',
            username: 'alice',
            color: '#E53935',
            latitude: 1.001,
            longitude: 2.001),
        Waypoint(
            id: 'fw2',
            name: "Alice's Work",
            userId: 'f1',
            username: 'alice',
            color: '#E53935',
            latitude: 1.002,
            longitude: 2.002),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('friendMarker_fw1')), findsOneWidget);
    expect(find.byKey(const Key('friendMarker_fw2')), findsOneWidget);
  });

  testWidgets('own nest marker uses a house icon, still red', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final ownMarker = markerLayer.markers.firstWhere((m) => m.key == const Key('ownNestMarker_w1'));
    final icon = (ownMarker.child as GestureDetector).child as Icon;
    expect(icon.icon, Icons.house);
    expect(icon.color, Colors.red);
  });

  testWidgets('tapping a friend marker shows their nest details in a dialog', (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            name: "Alice's Yard",
            userId: 'f1',
            username: 'alice',
            color: '#E53935',
            latitude: 1.001,
            longitude: 2.001,
            profilePictureUrl: 'https://example.com/alice.png'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friendMarker_fw1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nestDetailsDialog')), findsOneWidget);
    expect(find.text("alice's nest"), findsOneWidget);
    expect(find.text("Alice's Yard"), findsOneWidget);
    expect(find.text('(1.0010, 2.0010)'), findsOneWidget);
    // No edit action for a friend's nest.
    expect(find.byKey(const Key('editNestFromDialogButton')), findsNothing);
    // The picture fetch fails in the test harness (all HTTP is stubbed), so the avatar
    // falls back to the initial - exercises the same fallback path used elsewhere.
    expect(find.byKey(const Key('nestDetailsAvatar')), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('tapping the own nest marker shows "Your nest", the nest name, and an edit action',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nestDetailsDialog')), findsOneWidget);
    expect(find.text('Your nest'), findsOneWidget);
    expect(find.text('Backyard'), findsOneWidget);
    expect(find.text('(1.0000, 2.0000)'), findsOneWidget);
    expect(find.byKey(const Key('editNestFromDialogButton')), findsOneWidget);
  });

  testWidgets('shows a My Nests button in the app bar by default', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myNestsButton')), findsOneWidget);
  });

  testWidgets('pick-location mode hides the My Nests button and pops the tapped point',
      (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    LatLng? poppedPoint;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            poppedPoint = await Navigator.of(context).push<LatLng>(
              MaterialPageRoute(
                builder: (_) => MapScreen(
                  authState: authState,
                  waypointService: _FakeWaypointService(),
                  friendsService: _FakeFriendsService(),
                  profileService: _FakeProfileService(),
                  pickLocationMode: true,
                ),
              ),
            );
          },
          child: const Text('push'),
        ),
      ),
    ));

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myNestsButton')), findsNothing);

    tester.state<MapScreenState>(find.byType(MapScreen)).handleMapTap(const LatLng(5, 6));
    await tester.pumpAndSettle();

    expect(poppedPoint, const LatLng(5, 6));
    expect(find.byKey(const Key('waypointNameField')), findsNothing);
  });

  testWidgets('refresh() reloads data - needed since IndexedStack never rebuilds this screen',
      (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(id: 'fw1', name: "Alice's Yard", userId: 'f1', username: 'alice', color: '#E53935', latitude: 1.0, longitude: 2.0),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    // Simulate a color change that happened elsewhere in the app while this screen sat
    // alive but unbuilt in the IndexedStack.
    fakeFriendsService.friendWaypointsToReturn = [
      Waypoint(id: 'fw1', name: "Alice's Yard", userId: 'f1', username: 'alice', color: '#1E88E5', latitude: 1.0, longitude: 2.0),
    ];

    await tester.state<MapScreenState>(find.byType(MapScreen)).refresh();
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final friendMarker = markerLayer.markers.firstWhere((m) => m.key == const Key('friendMarker_fw1'));
    final icon = (friendMarker.child as GestureDetector).child as Icon;
    expect(icon.color, hexToColor('#1E88E5'));
  });
}
