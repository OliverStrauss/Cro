import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/birds_screen.dart';
import 'package:cro_app/screens/nest_birds_screen.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';

// A syntactically valid (unsigned) JWT with the given subject - BirdsScreen decodes this
// client-side to know the caller's own user id (same convention as MapScreen/ProfileScreen).
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({
        'alg': 'HS256'
      })}.${segment({
        'sub': userId
      })}.sig';
}

class _FakeWaypointService implements WaypointService {
  List<Waypoint> waypointsToReturn = [];
  Object? loadErrorToThrow;

  @override
  Future<List<Waypoint>> listWaypoints(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return waypointsToReturn;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeBirdService implements BirdService {
  List<Bird> birdsToReturn = [];
  Map<String, List<Bird>> residentsByNestId = {};
  Object? loadErrorToThrow;

  @override
  Future<List<Bird>> listBirds(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return birdsToReturn;
  }

  @override
  Future<List<Bird>> getNestResidents(String token, String nestId) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return residentsByNestId[nestId] ?? [];
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

Bird _bird(String id, {String? nestId, String ownerId = 'u1'}) => Bird(
      id: id,
      userId: ownerId,
      name: 'Bird $id',
      currentNestId: nestId,
      isTraveling: false,
      type: 'Sparrow',
    );

void main() {
  testWidgets('shows loading indicator before birds/nests load', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: _FakeWaypointService(),
        birdService: _FakeBirdService(),
      ),
    ));

    expect(find.byKey(const Key('birdsLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows a message when there are no nests and no birds', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: _FakeWaypointService(),
        birdService: _FakeBirdService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noBirdsMessage')), findsOneWidget);
  });

  testWidgets('lists each nest with its resident bird count', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Work', latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = [_bird('b1', nestId: 'w1'), _bird('b2', nestId: 'w1'), _bird('b3', nestId: 'w2')]
      ..residentsByNestId = {
        'w1': [_bird('b1', nestId: 'w1'), _bird('b2', nestId: 'w1')],
        'w2': [_bird('b3', nestId: 'w2')],
      };
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(authState: authState, waypointService: fakeWaypoints, birdService: fakeBirds),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdNestTile_w1')), findsOneWidget);
    expect(find.byKey(const Key('birdNestTile_w2')), findsOneWidget);
    expect(find.text('2 birds'), findsOneWidget);
    expect(find.text('1 bird'), findsOneWidget);
    expect(find.byKey(const Key('unassignedBirdsTile')), findsNothing);
  });

  testWidgets('shows an unread badge when a nest has unread residents', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final unreadBird = Bird(
      id: 'b1',
      userId: 'friend',
      name: 'Bird b1',
      currentNestId: 'w1',
      isTraveling: false,
      type: 'Sparrow',
      isRead: false,
    );
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = []
      ..residentsByNestId = {
        'w1': [unreadBird],
      };
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(authState: authState, waypointService: fakeWaypoints, birdService: fakeBirds),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unreadBadge_w1')), findsOneWidget);
    expect(find.textContaining('1 unread'), findsOneWidget);
  });

  testWidgets('shows an Unassigned row when some own birds have no nest', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = [_bird('b1', nestId: 'w1'), _bird('b2')]
      ..residentsByNestId = {
        'w1': [_bird('b1', nestId: 'w1')],
      };
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(authState: authState, waypointService: fakeWaypoints, birdService: fakeBirds),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unassignedBirdsTile')), findsOneWidget);
    expect(find.text('1 bird'), findsWidgets);
  });

  testWidgets('tapping a nest pushes the detail screen listing its birds\' names', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = [_bird('b1', nestId: 'w1')]
      ..residentsByNestId = {
        'w1': [_bird('b1', nestId: 'w1')],
      };
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(authState: authState, waypointService: fakeWaypoints, birdService: fakeBirds),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('birdNestTile_w1')));
    await tester.pumpAndSettle();

    expect(find.byType(NestBirdsScreen), findsOneWidget);
    expect(find.byKey(const Key('birdTile_b1')), findsOneWidget);
    expect(find.text('Bird b1'), findsOneWidget);
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService();
    final fakeBirds = _FakeBirdService()..loadErrorToThrow = BirdException('Could not load birds');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(authState: authState, waypointService: fakeWaypoints, birdService: fakeBirds),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdsErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
