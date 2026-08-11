import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/friend_bird.dart';
import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/utils/color_utils.dart';
import 'package:cro_app/widgets/avatar_with_fallback.dart';

class _FakeWaypointService implements WaypointService {
  List<Waypoint> waypointsToReturn = [];
  Object? errorToThrow;
  Waypoint? lastCreatedWaypoint;
  String? lastUploadedWaypointId;
  String? lastUploadedFilename;
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

  @override
  Future<String> uploadWaypointPicture(
    String token,
    String waypointId,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    lastUploadedWaypointId = waypointId;
    lastUploadedFilename = filename;
    return 'https://example.com/nest-pictures/$waypointId';
  }
}

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendWaypointsToReturn = [];
  List<FriendBird> friendsBirdsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<List<FriendBird>> getFriendsBirds(String token) async => friendsBirdsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

class _FakeProfileService implements ProfileService {
  UserProfile? profileToReturn = UserProfile(id: 'u1', username: 'me', email: 'me@example.com');
  XFile? imageToReturn;

  @override
  Future<UserProfile> getUser(String userId) async {
    if (profileToReturn == null) throw ProfileException('not found');
    return profileToReturn!;
  }

  // Used by the own-nest sheet's picture-change flow.
  @override
  Future<XFile?> pickImage() async => imageToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

class _FakeBirdService implements BirdService {
  List<Bird> birdsToReturn = [];
  Object? errorToThrow;
  int listBirdsCallCount = 0;
  String? lastSentBirdId;
  String? lastSentNestId;
  String? lastSentContent;

  @override
  Future<List<Bird>> listBirds(String token) async {
    listBirdsCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return birdsToReturn;
  }

  // Used by the own-nest sheet's "Birds here" send flow.
  @override
  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    lastSentBirdId = birdId;
    lastSentNestId = nestId;
    lastSentContent = content;
    return Bird(id: birdId, userId: 'u1', name: 'Bird $birdId', isTraveling: true, type: 'Sparrow');
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by MapScreen');
}

Bird _travelingBird(
  String id, {
  required String nestFromId,
  required String nestToId,
  DateTime? departedAt,
  DateTime? estimatedArrivalAt,
}) =>
    Bird(
      id: id,
      userId: 'u1',
      name: 'Bird $id',
      isTraveling: true,
      nestFromId: nestFromId,
      nestToId: nestToId,
      type: 'Sparrow',
      departedAt: departedAt ?? DateTime.now().subtract(const Duration(minutes: 1)),
      estimatedArrivalAt: estimatedArrivalAt ?? DateTime.now().add(const Duration(minutes: 1)),
    );

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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('friendMarker_fw1')), findsOneWidget);
    expect(find.byKey(const Key('friendMarker_fw2')), findsOneWidget);
  });

  testWidgets('own nest marker renders as a circular avatar bordered in Waypoint blue', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(
          id: 'w1',
          userId: 'u1',
          name: 'Backyard',
          latitude: 1.0,
          longitude: 2.0,
          profilePictureUrl: 'https://example.com/nest.png',
        )
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final ownMarker = markerLayer.markers.firstWhere((m) => m.key == const Key('ownNestMarker_w1'));
    final column = (ownMarker.child as GestureDetector).child as Column;
    final avatar = column.children.first as AvatarWithFallback;
    expect(avatar.imageUrl, 'https://example.com/nest.png');
    expect(avatar.borderColor, CroColors.waypointBlue);
  });

  testWidgets('tapping a friend marker shows their nest details in a sheet', (WidgetTester tester) async {
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friendMarker_fw1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nestDetailsSheet')), findsOneWidget);
    expect(find.text("alice's nest"), findsOneWidget);
    // Scoped to the sheet since the friend's map marker (now labeled with its own
    // nest-name pill) is still visible behind the sheet and would also match "Alice's Yard".
    expect(
      find.descendant(of: find.byKey(const Key('nestDetailsSheet')), matching: find.text("Alice's Yard")),
      findsOneWidget,
    );
    expect(find.text('(1.0010, 2.0010)'), findsOneWidget);
    // No edit action for a friend's nest.
    expect(find.byKey(const Key('editNestFromDialogButton')), findsNothing);
    // The picture fetch fails in the test harness (all HTTP is stubbed), so the avatar
    // falls back to the initial - exercises the same fallback path used elsewhere. Scoped
    // to the sheet's own avatar since the friend's map marker (also an AvatarWithFallback,
    // also falling back to "A") is still visible behind the sheet.
    expect(
      find.descendant(of: find.byKey(const Key('nestDetailsAvatar')), matching: find.text('A')),
      findsOneWidget,
    );
  });

  testWidgets('tapping the own nest marker shows "Your nest", the nest name, and coordinates - "This nest is empty" when it has no birds',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pumpAndSettle();

    // Same popup shape as a friend's nest - just with the extra own-nest content below.
    expect(find.byKey(const Key('nestDetailsSheet')), findsOneWidget);
    expect(find.text('Your nest'), findsOneWidget);
    expect(find.byKey(const Key('nestDetailsWaypointName')), findsOneWidget);
    expect(find.text('Backyard'), findsWidgets);
    expect(find.byKey(const Key('nestDetailsCoordinates')), findsOneWidget);
    expect(find.text('(1.0000, 2.0000)'), findsOneWidget);
    expect(find.byKey(const Key('renameNestButton')), findsOneWidget);
    expect(find.byKey(const Key('noBirdsAtNestMessage')), findsOneWidget);
    expect(find.text('This nest is empty'), findsOneWidget);
  });

  testWidgets('the own-nest sheet lists only the caller\'s own idle birds parked at that nest',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirdService = _FakeBirdService()
      ..birdsToReturn = [
        Bird(id: 'b1', userId: 'u1', name: 'Here', currentNestId: 'w1', isTraveling: false, type: 'Sparrow'),
        Bird(id: 'b2', userId: 'u1', name: 'Elsewhere', currentNestId: 'w2', isTraveling: false, type: 'Falcon'),
        _travelingBird('b3', nestFromId: 'w1', nestToId: 'w2'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: fakeBirdService),
    ));
    // Not pumpAndSettle(): b3 is traveling, which keeps the bob-animation controller
    // continuously repeating and never "settling" by design.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // let the sheet's slide-up transition finish

    // b1 is parked at w1 (shown), b2 is parked at a different own nest (not shown), b3 is
    // traveling (not "at" any nest yet, not shown).
    expect(find.byKey(const Key('birdTile_b1')), findsOneWidget);
    expect(find.byKey(const Key('birdTile_b2')), findsNothing);
    expect(find.byKey(const Key('birdTile_b3')), findsNothing);
    expect(find.byKey(const Key('noBirdsAtNestMessage')), findsNothing);
  });

  testWidgets('tapping one of the caller\'s own birds in the nest sheet sends it', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 3.0, longitude: 4.0),
      ];
    final fakeBirdService = _FakeBirdService()
      ..birdsToReturn = [
        Bird(id: 'b1', userId: 'u1', name: 'Here', currentNestId: 'w1', isTraveling: false, type: 'Sparrow'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: fakeBirdService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('birdTile_b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdDestinationDropdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sendBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(fakeBirdService.lastSentBirdId, 'b1');
    expect(fakeBirdService.lastSentNestId, 'w2');
    expect(find.byKey(const Key('birdTile_b1')), findsNothing);
    expect(find.byKey(const Key('noBirdsAtNestMessage')), findsOneWidget);
  });

  testWidgets('picking and uploading a nest picture from the sheet calls uploadWaypointPicture',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final fakeProfileService = _FakeProfileService()
      ..imageToReturn = XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'nest.png', mimeType: 'image/png');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: fakeProfileService,
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nestPictureButton')));
    await tester.pumpAndSettle();

    expect(fakeWaypointService.lastUploadedWaypointId, 'w1');
    expect(fakeWaypointService.lastUploadedFilename, 'nest.png');
    expect(find.text('Nest picture updated'), findsOneWidget);
  });

  testWidgets('renaming from within the own-nest sheet updates the displayed name', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Backyard', latitude: 1.0, longitude: 2.0)];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ownNestMarker_w1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('renameNestButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypointNameField')), 'Treehouse');
    await tester.tap(find.byKey(const Key('saveWaypointButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nestDetailsWaypointName')), findsOneWidget);
    expect(find.text('Treehouse'), findsWidgets);
  });

  testWidgets('a friend\'s nest sheet has no picture/rename affordances or bird list', (WidgetTester tester) async {
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            userId: 'friend1',
            name: "Friend's Nest",
            latitude: 1.002,
            longitude: 2.002,
            username: 'friendo',
            color: '#1E88E5'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friendMarker_fw1')));
    await tester.pumpAndSettle();

    // Same popup shape as an own nest (avatar, title, name, coordinates) - just without
    // the own-nest-only editing/bird-list content.
    expect(find.byKey(const Key('nestDetailsSheet')), findsOneWidget);
    expect(find.byKey(const Key('nestDetailsAvatar')), findsOneWidget);
    expect(find.byKey(const Key('nestDetailsWaypointName')), findsOneWidget);
    expect(find.byKey(const Key('nestDetailsCoordinates')), findsOneWidget);
    expect(find.byKey(const Key('renameNestButton')), findsNothing);
    expect(find.byKey(const Key('noBirdsAtNestMessage')), findsNothing);
    expect(find.text('Birds here'), findsNothing);
  });

  testWidgets('shows a My Nests button in the app bar by default', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
                  birdService: _FakeBirdService(),
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
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
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
    final column = (friendMarker.child as GestureDetector).child as Column;
    final avatar = column.children.first as AvatarWithFallback;
    expect(avatar.borderColor, hexToColor('#1E88E5'));
  });

  testWidgets('renders a flight-path line and moving marker for an in-flight own bird',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 1.001, longitude: 2.001),
      ];
    final fakeBirdService = _FakeBirdService()
      ..birdsToReturn = [_travelingBird('b1', nestFromId: 'w1', nestToId: 'w2')];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: fakeBirdService),
    ));
    // Not pumpAndSettle(): a traveling bird keeps the bob-animation controller
    // continuously repeating, which never "settles" by design.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('birdMarker_b1')), findsOneWidget);
    // find.byType(PolylineLayer) doesn't match a generic PolylineLayer<String> instance
    // (exact-runtimeType comparison vs. a specific generic instantiation) - use an `is`
    // predicate instead, which does the right thing for generics.
    final polylineLayerFinder = find.byWidgetPredicate((w) => w is PolylineLayer);
    expect(polylineLayerFinder, findsOneWidget);
    final polylineLayer = tester.widget(polylineLayerFinder) as PolylineLayer;
    expect(polylineLayer.polylines.map((p) => p.hitValue), contains('b1'));
  });

  testWidgets('tapping an own bird marker opens the bird details sheet, sent by "You"', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [
        Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
        Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 1.001, longitude: 2.001),
      ];
    final fakeBirdService = _FakeBirdService()
      ..birdsToReturn = [_travelingBird('b1', nestFromId: 'w1', nestToId: 'w2')];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: fakeBirdService),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('birdMarker_b1')));
    // Not pumpAndSettle(): the bob-animation controller is still repeating in the
    // background while this sheet is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('birdDetailsSheet')), findsOneWidget);
    expect(find.text('Bird b1'), findsOneWidget);
    expect(find.text('Sparrow · Sent by You'), findsOneWidget);
    expect(find.text('Cabin', skipOffstage: false), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const Key('birdDetailsDestination'))).data, 'Cabin');
  });

  testWidgets('tapping a friend\'s bird marker opens the bird details sheet, sent by their username',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            userId: 'friend1',
            name: "Friend's Nest",
            latitude: 1.002,
            longitude: 2.002,
            username: 'friendo',
            color: '#1E88E5'),
      ]
      ..friendsBirdsToReturn = [
        FriendBird(
          id: 'fb1',
          userId: 'friend1',
          username: 'friendo',
          color: '#1E88E5',
          name: "Friendo's Bird",
          type: 'Sparrow',
          nestFromId: 'fw1',
          nestToId: 'w1',
          departedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('birdMarker_fb1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('birdDetailsSheet')), findsOneWidget);
    expect(find.text("Friendo's Bird"), findsOneWidget);
    expect(find.text('Sparrow · Sent by friendo'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('birdDetailsDestination'))).data, 'Home');
  });

  testWidgets('renders a flight-path line and moving marker for a friend\'s in-flight bird, colored by sender',
      (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            userId: 'friend1',
            name: "Friend's Nest",
            latitude: 1.002,
            longitude: 2.002,
            username: 'friendo',
            color: '#1E88E5'),
      ]
      ..friendsBirdsToReturn = [
        FriendBird(
          id: 'fb1',
          userId: 'friend1',
          username: 'friendo',
          color: '#1E88E5',
          name: "Friendo's Bird",
          type: 'Sparrow',
          nestFromId: 'fw1',
          nestToId: 'w1',
          departedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    // Not pumpAndSettle(): a traveling bird keeps the bob-animation controller
    // continuously repeating, which never "settles" by design.
    await tester.pump();
    await tester.pump();

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final birdMarker = markerLayer.markers.firstWhere((m) => m.key == const Key('birdMarker_fb1'));
    final animatedBuilder = (birdMarker.child as GestureDetector).child as AnimatedBuilder;
    final marker = animatedBuilder.child as BirdTravelMarker;
    expect(marker.color, hexToColor('#1E88E5'));

    final polylineLayerFinder = find.byWidgetPredicate((w) => w is PolylineLayer);
    final polylineLayer = tester.widget(polylineLayerFinder) as PolylineLayer;
    final polyline = polylineLayer.polylines.singleWhere((p) => p.hitValue == 'fb1');
    expect(polyline.color, hexToColor('#1E88E5'));
  });

  testWidgets('a non-traveling bird gets no marker or line', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeBirdService = _FakeBirdService()
      ..birdsToReturn = [
        Bird(id: 'b1', userId: 'u1', name: 'Bird b1', currentNestId: 'w1', isTraveling: false, type: 'Sparrow'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: fakeBirdService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdMarker_b1')), findsNothing);
    expect(find.byWidgetPredicate((w) => w is PolylineLayer), findsNothing);
  });

  testWidgets('legend shows "You" plus one row per distinct friend visible on the map', (WidgetTester tester) async {
    final fakeWaypointService = _FakeWaypointService()
      ..waypointsToReturn = [Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0)];
    final fakeFriendsService = _FakeFriendsService()
      ..friendWaypointsToReturn = [
        Waypoint(
            id: 'fw1',
            userId: 'f1',
            name: "Alice's Yard",
            username: 'alice',
            color: '#E53935',
            latitude: 1.001,
            longitude: 2.001),
      ];
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: fakeWaypointService,
          friendsService: fakeFriendsService,
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mapLegend')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('mapLegend')), matching: find.text('You')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('mapLegend')), matching: find.text('alice')), findsOneWidget);
  });

  testWidgets('legend is hidden when there are no own nests or friends to show', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
          authState: authState,
          waypointService: _FakeWaypointService(),
          friendsService: _FakeFriendsService(),
          profileService: _FakeProfileService(),
          birdService: _FakeBirdService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mapLegend')), findsNothing);
  });

  group('curvedFlightPathPoints', () {
    final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
    final destination = Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 0.0, longitude: 1.0);

    test('starts exactly at the origin and ends exactly at the destination', () {
      final points = curvedFlightPathPoints(origin: origin, destination: destination);
      expect(points.first.latitude, closeTo(origin.latitude, 1e-9));
      expect(points.first.longitude, closeTo(origin.longitude, 1e-9));
      expect(points.last.latitude, closeTo(destination.latitude, 1e-9));
      expect(points.last.longitude, closeTo(destination.longitude, 1e-9));
    });

    test('bows away from the straight line at the midpoint, unlike a straight polyline', () {
      final points = curvedFlightPathPoints(origin: origin, destination: destination);
      final midpoint = points[points.length ~/ 2];
      // The straight line from (0,0) to (0,1) sits exactly on latitude 0 - a curved path's
      // midpoint should be offset away from it, not sitting on top of the straight line.
      expect(midpoint.latitude, isNot(closeTo(0.0, 1e-6)));
    });
  });

  group('interpolatedBirdPosition', () {
    final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
    final destination = Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 10.0, longitude: 20.0);
    final departedAt = DateTime(2026, 1, 1, 0, 0, 0);
    final estimatedArrivalAt = DateTime(2026, 1, 1, 1, 0, 0); // 1 hour flight

    // Not the lat/lng midpoint (5.0, 10.0), and not the straight-line chord's midpoint
    // either: the marker follows the same bowed curve PolylineLayer draws (see
    // curvedFlightPathPoints), so at 50% elapsed it should land exactly on that curve's
    // t=0.5 sample - which is what actually keeps the marker glued to the drawn line at
    // every point along the flight, not just at the endpoints.
    test('at 50% elapsed, lands exactly on the curved flight path, not the straight-line midpoint', () {
      final position = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        now: departedAt.add(const Duration(minutes: 30)),
      );
      final curveMidpoint = curvedFlightPathPoints(origin: origin, destination: destination)[10];
      expect(position.latitude, closeTo(curveMidpoint.latitude, 1e-9));
      expect(position.longitude, closeTo(curveMidpoint.longitude, 1e-9));
      expect(position.latitude, isNot(closeTo(5.0, 0.01)));
    });

    test('clamps to the destination once now is past the ETA', () {
      final position = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        now: estimatedArrivalAt.add(const Duration(hours: 5)),
      );
      expect(position.latitude, destination.latitude);
      expect(position.longitude, destination.longitude);
    });

    test('clamps to the origin if now is before departure (clock skew)', () {
      final position = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        now: departedAt.subtract(const Duration(minutes: 5)),
      );
      expect(position.latitude, origin.latitude);
      expect(position.longitude, origin.longitude);
    });

    test('returns the destination when the flight duration is zero', () {
      final position = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: departedAt,
        now: departedAt,
      );
      expect(position.latitude, destination.latitude);
      expect(position.longitude, destination.longitude);
    });

    test('returns the destination when the flight duration is negative', () {
      final position = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: departedAt.subtract(const Duration(minutes: 1)),
        now: departedAt,
      );
      expect(position.latitude, destination.latitude);
      expect(position.longitude, destination.longitude);
    });
  });

  group('positionAtFraction', () {
    final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
    final destination = Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 10.0, longitude: 20.0);

    test('matches interpolatedBirdPosition at the same fraction of elapsed time', () {
      final departedAt = DateTime(2026, 1, 1, 0, 0, 0);
      final estimatedArrivalAt = DateTime(2026, 1, 1, 1, 0, 0);
      final viaTime = interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        now: departedAt.add(const Duration(minutes: 30)),
      );
      final viaFraction = positionAtFraction(origin: origin, destination: destination, fraction: 0.5);

      expect(viaFraction.latitude, viaTime.latitude);
      expect(viaFraction.longitude, viaTime.longitude);
    });

    test('clamps fractions outside [0, 1] to the exact origin/destination', () {
      expect(positionAtFraction(origin: origin, destination: destination, fraction: -1).latitude, origin.latitude);
      expect(
        positionAtFraction(origin: origin, destination: destination, fraction: 2).latitude,
        destination.latitude,
      );
    });
  });

  group('bearingDegrees', () {
    test('a due-east flight line bears 90 degrees', () {
      final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
      final destination = Waypoint(id: 'w2', userId: 'u1', name: 'East', latitude: 0.0, longitude: 10.0);

      expect(bearingDegrees(origin: origin, destination: destination), closeTo(90.0, 0.01));
    });

    test('a due-north flight line bears 0 degrees', () {
      final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
      final destination = Waypoint(id: 'w2', userId: 'u1', name: 'North', latitude: 10.0, longitude: 0.0);

      expect(bearingDegrees(origin: origin, destination: destination), closeTo(0.0, 0.01));
    });

    test('a due-south flight line bears 180 degrees', () {
      final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 10.0, longitude: 0.0);
      final destination = Waypoint(id: 'w2', userId: 'u1', name: 'South', latitude: 0.0, longitude: 0.0);

      expect(bearingDegrees(origin: origin, destination: destination), closeTo(180.0, 0.01));
    });

    test('a due-west flight line bears 270 degrees', () {
      final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 10.0);
      final destination = Waypoint(id: 'w2', userId: 'u1', name: 'West', latitude: 0.0, longitude: 0.0);

      expect(bearingDegrees(origin: origin, destination: destination), closeTo(270.0, 0.01));
    });

    test('at a given fraction, matches the curved path\'s tangent direction rather than the fixed chord bearing', () {
      final origin = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 0.0, longitude: 0.0);
      final destination = Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 5.0, longitude: 10.0);

      final atStart = bearingDegrees(origin: origin, destination: destination, fraction: 0.0);
      final atMidpoint = bearingDegrees(origin: origin, destination: destination); // default fraction: 0.5
      final atEnd = bearingDegrees(origin: origin, destination: destination, fraction: 1.0);

      // The path bows, so a bird following it turns over the course of the flight - the
      // heading near the start and end shouldn't match the midpoint chord bearing.
      expect(atStart, isNot(closeTo(atMidpoint, 0.01)));
      expect(atEnd, isNot(closeTo(atMidpoint, 0.01)));
    });
  });

  group('elapsedFraction', () {
    final departedAt = DateTime(2026, 1, 1, 0, 0, 0);
    final estimatedArrivalAt = DateTime(2026, 1, 1, 1, 0, 0);

    test('returns 0.5 at the halfway point of the flight', () {
      final fraction = elapsedFraction(
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        now: departedAt.add(const Duration(minutes: 30)),
      );
      expect(fraction, closeTo(0.5, 0.0001));
    });

    test('returns 1.0 when the flight duration is zero or negative', () {
      expect(
        elapsedFraction(departedAt: departedAt, estimatedArrivalAt: departedAt, now: departedAt),
        1.0,
      );
      expect(
        elapsedFraction(
          departedAt: departedAt,
          estimatedArrivalAt: departedAt.subtract(const Duration(minutes: 1)),
          now: departedAt,
        ),
        1.0,
      );
    });
  });

  group('live updates', () {
    testWidgets('does not poll for bird updates unless startLiveUpdates() has been called',
        (WidgetTester tester) async {
      final fakeBirdService = _FakeBirdService();
      final authState = AuthState()..login(_fakeJwtFor('u1'));
      await tester.pumpWidget(MaterialApp(
        home: MapScreen(
            authState: authState,
            waypointService: _FakeWaypointService(),
            friendsService: _FakeFriendsService(),
            profileService: _FakeProfileService(),
            birdService: fakeBirdService),
      ));
      await tester.pumpAndSettle();
      expect(fakeBirdService.listBirdsCallCount, 1);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));

      expect(fakeBirdService.listBirdsCallCount, 1);
    });

    testWidgets('startLiveUpdates() polls birds every 3 seconds while running',
        (WidgetTester tester) async {
      final fakeBirdService = _FakeBirdService();
      final authState = AuthState()..login(_fakeJwtFor('u1'));
      await tester.pumpWidget(MaterialApp(
        home: MapScreen(
            authState: authState,
            waypointService: _FakeWaypointService(),
            friendsService: _FakeFriendsService(),
            profileService: _FakeProfileService(),
            birdService: fakeBirdService),
      ));
      await tester.pumpAndSettle();
      final mapState = tester.state<MapScreenState>(find.byType(MapScreen));
      final countAfterLoad = fakeBirdService.listBirdsCallCount;

      mapState.startLiveUpdates();
      await tester.pump(const Duration(seconds: 3));
      expect(fakeBirdService.listBirdsCallCount, countAfterLoad + 1);

      await tester.pump(const Duration(seconds: 3));
      expect(fakeBirdService.listBirdsCallCount, countAfterLoad + 2);

      await tester.pump(const Duration(seconds: 3));
      expect(fakeBirdService.listBirdsCallCount, countAfterLoad + 3);

      mapState.stopLiveUpdates();
    });

    testWidgets("a bird's marker and flight line disappear after it arrives",
        (WidgetTester tester) async {
      final fakeWaypointService = _FakeWaypointService()
        ..waypointsToReturn = [
          Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0),
          Waypoint(id: 'w2', userId: 'u1', name: 'Cabin', latitude: 1.001, longitude: 2.001),
        ];
      final fakeBirdService = _FakeBirdService()
        ..birdsToReturn = [_travelingBird('b1', nestFromId: 'w1', nestToId: 'w2')];
      final authState = AuthState()..login(_fakeJwtFor('u1'));
      await tester.pumpWidget(MaterialApp(
        home: MapScreen(
            authState: authState,
            waypointService: fakeWaypointService,
            friendsService: _FakeFriendsService(),
            profileService: _FakeProfileService(),
            birdService: fakeBirdService),
      ));
      // Not pumpAndSettle(): a traveling bird keeps the bob-animation controller
      // continuously repeating, which never "settles" by design.
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('birdMarker_b1')), findsOneWidget);

      // Simulate the server having lazily resolved the arrival on the next poll.
      fakeBirdService.birdsToReturn = [
        Bird(id: 'b1', userId: 'u1', name: 'Bird b1', currentNestId: 'w2', isTraveling: false, type: 'Sparrow'),
      ];

      final mapState = tester.state<MapScreenState>(find.byType(MapScreen));
      mapState.startLiveUpdates();
      await tester.pump(const Duration(seconds: 3));

      expect(find.byKey(const Key('birdMarker_b1')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is PolylineLayer), findsNothing);

      mapState.stopLiveUpdates();
    });

    testWidgets('dispose() cancels the live-update timer', (WidgetTester tester) async {
      final fakeBirdService = _FakeBirdService();
      final authState = AuthState()..login(_fakeJwtFor('u1'));
      await tester.pumpWidget(MaterialApp(
        home: MapScreen(
            authState: authState,
            waypointService: _FakeWaypointService(),
            friendsService: _FakeFriendsService(),
            profileService: _FakeProfileService(),
            birdService: fakeBirdService),
      ));
      await tester.pumpAndSettle();

      tester.state<MapScreenState>(find.byType(MapScreen)).startLiveUpdates();

      // Swap the widget tree out without calling stopLiveUpdates() first - if dispose()
      // ever loses its cancel call, this leaves a pending Timer and the test fails at
      // teardown with a "Timer is still pending" error.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
    });
  });
}
