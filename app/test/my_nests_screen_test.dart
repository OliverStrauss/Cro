import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/screens/my_nests_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';

class _FakeWaypointService implements WaypointService {
  List<Waypoint> waypointsToReturn = [];
  Object? loadErrorToThrow;
  Object? createErrorToThrow;

  String? lastCreatedName;
  double? lastCreatedLatitude;
  double? lastCreatedLongitude;
  String? lastUpdatedId;
  String? lastUpdatedName;
  String? lastDeletedId;

  @override
  Future<List<Waypoint>> listWaypoints(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return waypointsToReturn;
  }

  @override
  Future<Waypoint> createWaypoint(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    if (createErrorToThrow != null) throw createErrorToThrow!;
    lastCreatedName = name;
    lastCreatedLatitude = latitude;
    lastCreatedLongitude = longitude;
    final created = Waypoint(id: 'new-id', userId: 'u1', name: name, latitude: latitude, longitude: longitude);
    waypointsToReturn = [...waypointsToReturn, created];
    return created;
  }

  @override
  Future<Waypoint> updateWaypoint(
    String token,
    String id, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    lastUpdatedId = id;
    lastUpdatedName = name;
    waypointsToReturn = waypointsToReturn
        .map((w) => w.id == id
            ? Waypoint(id: w.id, userId: w.userId, name: name, latitude: latitude, longitude: longitude)
            : w)
        .toList();
    return waypointsToReturn.firstWhere((w) => w.id == id);
  }

  @override
  Future<void> deleteWaypoint(String token, String id) async {
    lastDeletedId = id;
    waypointsToReturn = waypointsToReturn.where((w) => w.id != id).toList();
  }

  @override
  Future<String> uploadWaypointPicture(
    String token,
    String waypointId,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async =>
      'https://example.com/nest-pictures/$waypointId';
}

class _FakeFriendsService implements FriendsService {
  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => [];

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<UserProfile> getUser(String userId) async =>
      UserProfile(id: userId, username: 'me', email: 'me@example.com');

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  testWidgets('shows loading indicator before nests load', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));

    expect(find.byKey(const Key('myNestsLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows a message when there are no nests', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noNestsMessage')), findsOneWidget);
  });

  testWidgets('lists each nest with its name and coordinates', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Work', latitude: 3.0, longitude: 4.0),
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nestTile_w1')), findsOneWidget);
    expect(find.byKey(const Key('nestTile_w2')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.byKey(const Key('noNestsMessage')), findsNothing);
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()..loadErrorToThrow = WaypointException('Could not load nests');
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myNestsErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('renaming a nest calls updateWaypoint with the new name and refreshes',
      (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('renameNestButton_w1')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('waypointNameField')));
    expect(field.controller!.text, 'Home');

    await tester.enterText(find.byKey(const Key('waypointNameField')), 'Cabin');
    await tester.tap(find.byKey(const Key('saveWaypointButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastUpdatedId, 'w1');
    expect(fakeService.lastUpdatedName, 'Cabin');
    expect(find.text('Cabin'), findsOneWidget);
  });

  testWidgets('deleting a nest confirms, then calls deleteWaypoint and refreshes', (WidgetTester tester) async {
    final fakeService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(authState: authState, waypointService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deleteNestButton_w1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmDeleteNestButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastDeletedId, 'w1');
    expect(find.byKey(const Key('nestTile_w1')), findsNothing);
    expect(find.byKey(const Key('noNestsMessage')), findsOneWidget);
  });

  testWidgets('add flow picks a spot on the map, names it, and creates a nest', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: MyNestsScreen(
        authState: authState,
        waypointService: fakeWaypointService,
        friendsService: _FakeFriendsService(),
        profileService: _FakeProfileService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addNestButton')));
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);

    tester.state<MapScreenState>(find.byType(MapScreen)).handleMapTap(const LatLng(9, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypointNameField')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('waypointNameField')), 'New Spot');
    await tester.tap(find.byKey(const Key('saveWaypointButton')));
    await tester.pumpAndSettle();

    expect(fakeWaypointService.lastCreatedName, 'New Spot');
    expect(fakeWaypointService.lastCreatedLatitude, 9);
    expect(fakeWaypointService.lastCreatedLongitude, 10);
    expect(find.byType(MyNestsScreen), findsOneWidget);
    expect(find.text('New Spot'), findsOneWidget);
  });
}
