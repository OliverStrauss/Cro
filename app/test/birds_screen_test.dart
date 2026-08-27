import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/birds_screen.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';

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

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendsWaypointsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendsWaypointsToReturn;

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
  List<Bird> birdsToReturn = [];
  Object? loadErrorToThrow;
  String? lastSentBirdId;
  String? lastSentNestId;
  String? lastSentContent;
  String? lastRenamedBirdId;
  String? lastRenamedTo;
  String? lastDeletedBirdId;
  String? lastUploadedBirdId;

  @override
  Future<List<Bird>> listBirds(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return birdsToReturn;
  }

  @override
  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    lastSentBirdId = birdId;
    lastSentNestId = nestId;
    lastSentContent = content;
    final sent = birdsToReturn.firstWhere((b) => b.id == birdId);
    birdsToReturn = birdsToReturn
        .map((b) => b.id == birdId
            ? Bird(
                id: b.id,
                userId: b.userId,
                name: b.name,
                isTraveling: true,
                nestFromId: b.currentNestId,
                nestToId: nestId,
                type: b.type,
                content: content,
              )
            : b)
        .toList();
    return sent;
  }

  @override
  Future<Bird> renameBird(String token, String birdId, String name) async {
    lastRenamedBirdId = birdId;
    lastRenamedTo = name;
    final renamed = birdsToReturn.firstWhere((b) => b.id == birdId);
    final updated = Bird(
      id: renamed.id,
      userId: renamed.userId,
      name: name,
      currentNestId: renamed.currentNestId,
      isTraveling: renamed.isTraveling,
      nestToId: renamed.nestToId,
      type: renamed.type,
    );
    birdsToReturn = birdsToReturn.map((b) => b.id == birdId ? updated : b).toList();
    return updated;
  }

  @override
  Future<void> deleteBird(String token, String birdId) async {
    lastDeletedBirdId = birdId;
    birdsToReturn = birdsToReturn.where((b) => b.id != birdId).toList();
  }

  @override
  Future<XFile?> pickImage() async =>
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'bird.png', mimeType: 'image/png');

  @override
  Future<String> uploadBirdPicture(
    String token,
    String birdId,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    lastUploadedBirdId = birdId;
    return 'https://example.com/bird-pictures/$birdId';
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

Bird _bird(
  String id, {
  String? nestId,
  String? nestToId,
  bool isTraveling = false,
  String type = 'Sparrow',
  DateTime? estimatedArrivalAt,
}) =>
    Bird(
      id: id,
      userId: 'u1',
      name: 'Bird $id',
      currentNestId: nestId,
      isTraveling: isTraveling,
      nestToId: nestToId,
      type: type,
      estimatedArrivalAt: estimatedArrivalAt,
    );

void main() {
  testWidgets('shows loading indicator before data loads', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: _FakeWaypointService(),
        birdService: _FakeBirdService(),
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));

    expect(find.byKey(const Key('birdsLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows a message when the caller has no birds', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: _FakeWaypointService(),
        birdService: _FakeBirdService(),
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noBirdsMessage')), findsOneWidget);
  });

  testWidgets('shows a card per bird with its name, type, and location', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeFriends = _FakeFriendsService()
      ..friendsWaypointsToReturn = [
        Waypoint(id: 'w2', userId: 'friend', username: 'sam', name: "Sam's Cabin", latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = [
        _bird('b1', nestId: 'w1'), // resident in own nest
        _bird('b2', nestId: 'w2'), // resident in a friend's nest
        _bird(
          'b3',
          isTraveling: true,
          nestToId: 'w1',
          estimatedArrivalAt: DateTime.now().add(const Duration(hours: 3, minutes: 24)),
        ), // heading to own nest
        _bird('b4'), // unassigned
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: fakeFriends,
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdCard_b1')), findsOneWidget);
    expect(find.byKey(const Key('birdCard_b2')), findsOneWidget);
    expect(find.byKey(const Key('birdCard_b3')), findsOneWidget);
    expect(find.byKey(const Key('birdCard_b4')), findsOneWidget);

    expect(find.text('Bird b1'), findsOneWidget);
    expect(find.text('Sparrow'), findsWidgets);

    final location1 = tester.widget<Text>(find.byKey(const Key('birdLocation_b1')));
    expect(location1.data, 'Home');

    final location2 = tester.widget<Text>(find.byKey(const Key('birdLocation_b2')));
    expect(location2.data, "Sam's Cabin");

    final location3 = tester.widget<Text>(find.byKey(const Key('birdLocation_b3')));
    expect(location3.data, 'Heading to Home');

    final location4 = tester.widget<Text>(find.byKey(const Key('birdLocation_b4')));
    expect(location4.data, 'Unassigned');

    // Every card gets an avatar (falling back to an initial when no picture is set) that
    // can be tapped to upload a picture for that specific bird.
    expect(find.byKey(const Key('birdAvatar_b1')), findsOneWidget);
    expect(find.byKey(const Key('birdAvatar_b2')), findsOneWidget);
    expect(find.byKey(const Key('birdAvatar_b3')), findsOneWidget);
    expect(find.byKey(const Key('birdAvatar_b4')), findsOneWidget);

    // Only the traveling bird has an ETA line.
    final eta3 = tester.widget<Text>(find.byKey(const Key('birdEta_b3')));
    expect(eta3.data, startsWith('Arrives in 3h'));
    expect(find.byKey(const Key('birdEta_b1')), findsNothing);
    expect(find.byKey(const Key('birdEta_b2')), findsNothing);
    expect(find.byKey(const Key('birdEta_b4')), findsNothing);
  });

  testWidgets('tapping an idle, nested bird opens the destination picker and sends it',
      (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirds = _FakeBirdService()..birdsToReturn = [_bird('b1', nestId: 'w1')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('birdCard_b1')));
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

    final location1 = tester.widget<Text>(find.byKey(const Key('birdLocation_b1')));
    expect(location1.data, 'Heading to Cabin');
  });

  testWidgets('a traveling bird is not tappable', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()..birdsToReturn = [_bird('b1', isTraveling: true, nestToId: 'w1')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('birdCard_b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdDestinationDropdown')), findsNothing);
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService();
    final fakeBirds = _FakeBirdService()..loadErrorToThrow = BirdException('Could not load birds');
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdsErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a bird avatar uploads a new picture for that bird', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()..birdsToReturn = [_bird('b1', nestId: 'w1')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('birdAvatar_b1')));
    await tester.pumpAndSettle();

    expect(fakeBirds.lastUploadedBirdId, 'b1');
  });

  testWidgets('renaming a bird calls renameBird and refreshes', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()..birdsToReturn = [_bird('b1', nestId: 'w1')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('renameBirdButton_b1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('birdNameField')), 'Speedy');
    await tester.tap(find.byKey(const Key('saveBirdNameButton')));
    await tester.pumpAndSettle();

    expect(fakeBirds.lastRenamedBirdId, 'b1');
    expect(fakeBirds.lastRenamedTo, 'Speedy');
    expect(find.text('Speedy'), findsOneWidget);
  });

  testWidgets('deleting a bird requires a second confirming tap', (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()..birdsToReturn = [_bird('b1', nestId: 'w1')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deleteBirdButton_b1')));
    await tester.pumpAndSettle();
    expect(fakeBirds.lastDeletedBirdId, null);
    expect(find.text('Confirm?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteBirdButton_b1')));
    await tester.pumpAndSettle();

    expect(fakeBirds.lastDeletedBirdId, 'b1');
    expect(find.byKey(const Key('birdCard_b1')), findsNothing);
  });

  testWidgets('the spawn button shows a max-capacity message once 5 birds are owned',
      (WidgetTester tester) async {
    final fakeWaypoints = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirds = _FakeBirdService()
      ..birdsToReturn = List.generate(5, (i) => _bird('b$i', nestId: 'w1'));
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: BirdsScreen(
        authState: authState,
        waypointService: fakeWaypoints,
        birdService: fakeBirds,
        friendsService: _FakeFriendsService(),
        hubService: _FakeHubService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('spawnBirdButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('max 5 birds'), findsOneWidget);
  });
}
