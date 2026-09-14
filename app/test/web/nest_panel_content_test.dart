import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/pinned_bird.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/pin_service.dart';
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

class _FakeBirdService implements BirdService {
  List<Bird> residentsToReturn = [];

  @override
  Future<List<Bird>> getNestResidents(String token, String nestId) async => residentsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakePinService implements PinService {
  List<PinnedBird> publicPinsToReturn = [];

  @override
  Future<List<PinnedBird>> listPublicPins(String token) async => publicPinsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeFriendsService implements FriendsService {
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
    _FakePinService? pinService,
    ValueChanged<Bird>? onSelectBird,
    VoidCallback? onViewPinned,
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
          birdService: birdService ?? _FakeBirdService(),
          profileService: _FakeProfileService(),
          pinService: pinService ?? _FakePinService(),
          friendsService: _FakeFriendsService(),
          onChanged: () {},
          onSelectBird: onSelectBird ?? (_) {},
          onViewPinned: onViewPinned ?? () {},
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

  testWidgets('an own nest has a button that jumps to the Pinned screen', (tester) async {
    final nest = Waypoint(id: 'n1', userId: 'u1', name: 'Backyard', latitude: 1, longitude: 2);
    var tapped = false;
    await tester.pumpWidget(build(nest, isOwn: true, onViewPinned: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webViewPinnedNestButton')));
    expect(tapped, isTrue);
  });

  testWidgets('a friend nest shows that user\'s public pins, filtered from the world feed', (tester) async {
    final theirPin = PinnedBird(
      id: 'pin1',
      receiverId: 'u2',
      senderId: 'u3',
      senderUsername: 'Someone',
      birdId: 'b9',
      birdName: 'Otto',
      type: 'Cro',
      content: 'hi',
      isPublic: true,
      createdAt: DateTime.now(),
    );
    final someoneElsesPin = PinnedBird(
      id: 'pin2',
      receiverId: 'u4',
      senderId: 'u3',
      senderUsername: 'Someone',
      birdId: 'b8',
      birdName: 'Percy',
      type: 'Cro',
      content: 'hi',
      isPublic: true,
      createdAt: DateTime.now(),
    );
    final pinService = _FakePinService()..publicPinsToReturn = [theirPin, someoneElsesPin];

    await tester.pumpWidget(build(friendNest, isOwn: false, pinService: pinService));
    await tester.pumpAndSettle();

    expect(find.text('Public pins'), findsOneWidget);
    expect(find.byKey(const ValueKey('nestPanelPublicPin_pin1')), findsOneWidget);
    expect(find.byKey(const ValueKey('nestPanelPublicPin_pin2')), findsNothing);
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

  testWidgets('tapping a resident bird opens its own detail panel instead of a send flow', (tester) async {
    final myBirdHere = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'f1', isTraveling: false, type: 'Cro');
    Bird? selected;

    await tester.pumpWidget(build(
      friendNest,
      isOwn: false,
      ownBirds: [myBirdHere],
      onSelectBird: (bird) => selected = bird,
    ));
    await tester.pump();

    expect(find.text('Send →'), findsNothing);

    await tester.tap(find.byKey(const Key('nestPanelResident_b1')));
    await tester.pump();

    expect(selected?.id, 'b1');
  });
}
