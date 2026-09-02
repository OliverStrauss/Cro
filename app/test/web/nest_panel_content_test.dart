import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/web/widgets/nest_panel_content.dart';

class _FakeWaypointService implements WaypointService {
  List<Waypoint> ownNestsToReturn = [];

  @override
  Future<List<Waypoint>> listWaypoints(String token) async => ownNestsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendWaypointsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeHubService implements HubService {
  List<Hub> hubsToReturn = [];

  @override
  Future<List<Hub>> listHubs(String token) async => hubsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeBirdService implements BirdService {
  List<Bird> residentsToReturn = [];
  String? lastSentBirdId;
  String? lastSentNestId;

  @override
  Future<List<Bird>> getNestResidents(String token, String nestId) async => residentsToReturn;

  @override
  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    lastSentBirdId = birdId;
    lastSentNestId = nestId;
    return Bird(id: birdId, userId: 'u1', name: 'Sent', currentNestId: nestId, isTraveling: true, type: 'Cro');
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  // A syntactically valid (unsigned) JWT with a fixed subject - NestPanelContent decodes
  // this client-side to split "delivered to you" from "birds here" on an own-nest render.
  final authState = AuthState()..login('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.sig');

  Widget build(
    Waypoint nest, {
    required bool isOwn,
    List<Bird> ownBirds = const [],
    _FakeBirdService? birdService,
    _FakeWaypointService? waypointService,
    _FakeFriendsService? friendsService,
    _FakeHubService? hubService,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NestPanelContent(
          nest: nest,
          isOwn: isOwn,
          ownBirds: ownBirds,
          authState: authState,
          onClose: () {},
          waypointService: waypointService ?? _FakeWaypointService(),
          friendsService: friendsService ?? _FakeFriendsService(),
          hubService: hubService ?? _FakeHubService(),
          birdService: birdService ?? _FakeBirdService(),
          profileService: _FakeProfileService(),
          onChanged: () {},
        ),
      ),
    );
  }

  final friendNest = Waypoint(
    id: 'f1',
    userId: 'u2',
    name: "Mia's Cabin",
    latitude: 1,
    longitude: 2,
    username: 'mia',
    color: '#E53935',
  );

  testWidgets('a friend nest with nothing of the caller\'s there renders just the minimal header',
      (tester) async {
    await tester.pumpWidget(build(friendNest, isOwn: false));
    await tester.pump();

    expect(find.text("mia's nest"), findsOneWidget);
    expect(find.text("Mia's Cabin"), findsOneWidget);
    expect(find.textContaining('will find it waiting'), findsNothing);
    expect(find.textContaining('never what is inside it'), findsNothing);
    expect(find.byKey(const Key('webRenameNestButton')), findsNothing);
    expect(find.text('Your birds here'), findsNothing);
  });

  testWidgets('an own nest still shows the normal "Birds here" body', (tester) async {
    final nest = Waypoint(id: 'n1', userId: 'u1', name: 'Backyard', latitude: 1, longitude: 2);
    await tester.pumpWidget(build(nest, isOwn: true));
    await tester.pumpAndSettle();

    expect(find.text('Your nest'), findsOneWidget);
    expect(find.text('Birds here'), findsOneWidget);
    expect(find.byKey(const Key('nestPanelEmpty')), findsOneWidget);
    expect(find.byKey(const Key('webRenameNestButton')), findsOneWidget);
  });

  testWidgets('a friend nest with one of the caller\'s own birds there lists it, reusing the resident row',
      (tester) async {
    // Like Oliver's bird at Annie's nest: it's already landed there (not traveling), so it
    // shows up in the caller's own full bird list with currentNestId pointing at this nest.
    final myBirdHere = Bird(
      id: 'b1',
      userId: 'u1',
      name: 'Otto',
      currentNestId: 'f1',
      isTraveling: false,
      type: 'Cro',
    );
    // A bird still traveling toward this nest, or resting at a different one, shouldn't show.
    final stillFlying = Bird(
      id: 'b2',
      userId: 'u1',
      name: 'Percy',
      isTraveling: true,
      nestFromId: 'n1',
      nestToId: 'f1',
      type: 'Sparrow',
    );
    final elsewhere = Bird(id: 'b3', userId: 'u1', name: 'Fen', currentNestId: 'n1', isTraveling: false, type: 'Cro');

    await tester.pumpWidget(build(friendNest, isOwn: false, ownBirds: [myBirdHere, stillFlying, elsewhere]));
    await tester.pump();

    expect(find.text('Your birds here'), findsOneWidget);
    expect(find.byKey(const Key('nestPanelResident_b1')), findsOneWidget);
    expect(find.text('Otto'), findsOneWidget);
    expect(find.byKey(const Key('nestPanelResident_b2')), findsNothing);
    expect(find.byKey(const Key('nestPanelResident_b3')), findsNothing);
  });

  testWidgets(
      'sending a bird onward from a friend nest excludes that same friend nest from the destination list, but offers hubs',
      (tester) async {
    final myBirdHere = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'f1', isTraveling: false, type: 'Cro');
    final home = Waypoint(id: 'n1', userId: 'u1', name: 'Home', latitude: 0, longitude: 0);
    final anotherFriendNest =
        Waypoint(id: 'f2', userId: 'u3', name: "Bob's Yard", latitude: 3, longitude: 4, username: 'bob');
    final hub = Hub(id: 'h1', name: 'Lighthouse', latitude: 44, longitude: -91, status: 'Approved', createdByUserId: 'admin');
    final fakeBirdService = _FakeBirdService();
    final fakeWaypointService = _FakeWaypointService()..ownNestsToReturn = [home];
    // getFriendsWaypoints returns every friend nest including the one currently being
    // viewed (f1 itself) - _openSendFlow must filter that out itself, not rely on the caller.
    final fakeFriendsService = _FakeFriendsService()..friendWaypointsToReturn = [friendNest, anotherFriendNest];
    final fakeHubService = _FakeHubService()..hubsToReturn = [hub];

    await tester.pumpWidget(build(
      friendNest,
      isOwn: false,
      ownBirds: [myBirdHere],
      birdService: fakeBirdService,
      waypointService: fakeWaypointService,
      friendsService: fakeFriendsService,
      hubService: fakeHubService,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('nestPanelResident_b1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sendBirdDestinationDropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text("Bob's Yard (bob)"), findsOneWidget);
    expect(find.text("Mia's Cabin (mia)"), findsNothing);
    expect(find.text('Lighthouse (Hub)'), findsOneWidget);

    await tester.tap(find.text('Lighthouse (Hub)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(fakeBirdService.lastSentBirdId, 'b1');
    expect(fakeBirdService.lastSentNestId, 'h1');
  });
}
