import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/nest_birds_screen.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';

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

  @override
  Future<List<Waypoint>> listWaypoints(String token) async => waypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendsWaypointsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendsWaypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeBirdService implements BirdService {
  String? lastSentBirdId;
  String? lastSentNestId;
  String? lastSentContent;
  String? lastReadBirdId;

  @override
  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    lastSentBirdId = birdId;
    lastSentNestId = nestId;
    lastSentContent = content;
    return Bird(id: birdId, userId: 'u1', name: 'Bird $birdId', isTraveling: true, type: 'Sparrow');
  }

  @override
  Future<Bird> markBirdRead(String token, String birdId) async {
    lastReadBirdId = birdId;
    return Bird(id: birdId, userId: 'friend', name: 'Bird $birdId', isTraveling: false, type: 'Sparrow', isRead: true);
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  testWidgets("tapping the caller's own idle bird opens the destination picker and sends",
      (WidgetTester tester) async {
    final ownBird = Bird(id: 'b1', userId: 'u1', name: 'Bird 1', currentNestId: 'w1', isTraveling: false, type: 'Sparrow');
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirds = _FakeBirdService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));

    await tester.pumpWidget(MaterialApp(
      home: NestBirdsScreen(
        title: 'Home',
        nestId: 'w1',
        birds: [ownBird],
        callerUserId: 'u1',
        birdService: fakeBirds,
        waypointService: fakeWaypoints,
        friendsService: _FakeFriendsService(),
        authState: authState,
      ),
    ));

    await tester.tap(find.byKey(const Key('birdTile_b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdDestinationDropdown')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sendBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabin').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('sendBirdMessageField')), 'Hi there');
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(fakeBirds.lastSentBirdId, 'b1');
    expect(fakeBirds.lastSentNestId, 'w2');
    expect(fakeBirds.lastSentContent, 'Hi there');
    expect(find.byKey(const Key('birdTile_b1')), findsNothing);
  });

  testWidgets("tapping someone else's resident bird shows its message and marks it read",
      (WidgetTester tester) async {
    final friendBird = Bird(
      id: 'b2',
      userId: 'friend',
      name: 'Bird 2',
      currentNestId: 'w1',
      isTraveling: false,
      type: 'Falcon',
      content: 'Hello from afar',
      isRead: false,
    );
    final fakeBirds = _FakeBirdService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));

    await tester.pumpWidget(MaterialApp(
      home: NestBirdsScreen(
        title: 'Home',
        nestId: 'w1',
        birds: [friendBird],
        callerUserId: 'u1',
        birdService: fakeBirds,
        waypointService: _FakeWaypointService(),
        friendsService: _FakeFriendsService(),
        authState: authState,
      ),
    ));

    expect(find.byKey(const Key('unreadDot_b2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('birdTile_b2')));
    await tester.pumpAndSettle();

    expect(find.text('Hello from afar'), findsOneWidget);
    expect(fakeBirds.lastReadBirdId, 'b2');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unreadDot_b2')), findsNothing);
  });
}
