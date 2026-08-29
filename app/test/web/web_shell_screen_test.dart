import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/blocked_user.dart';
import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_bird.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/hub_message.dart';
import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/models/user_search_result.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/models/event.dart';
import 'package:cro_app/web/screens/web_shell_screen.dart';
import 'package:cro_app/web/services/event_service.dart';

class _FakeWaypointService implements WaypointService {
  List<Waypoint> waypointsToReturn = [];

  @override
  Future<List<Waypoint>> listWaypoints(String token) async => waypointsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeFriendsService implements FriendsService {
  List<Waypoint> friendWaypointsToReturn = [];
  List<FriendBird> friendsBirdsToReturn = [];
  List<FriendRequest> incomingToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<List<FriendBird>> getFriendsBirds(String token) async => friendsBirdsToReturn;

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => incomingToReturn;

  @override
  Future<List<Friend>> getFriends(String token) async => [];

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async => [];

  @override
  Future<List<BlockedUser>> getBlockedUsers(String token) async => [];

  @override
  Future<List<UserSearchResult>> searchUsers(String token, String query) async => [];

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeBirdService implements BirdService {
  List<Bird> birdsToReturn = [];

  @override
  Future<List<Bird>> listBirds(String token) async => birdsToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeHubService implements HubService {
  List<Hub> hubsToReturn = [];

  @override
  Future<List<Hub>> listHubs(String token) async => hubsToReturn;

  @override
  Future<List<HubMessage>> listMessages(String token, String hubId) async => [];

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeProfileService implements ProfileService {
  UserProfile profileToReturn = UserProfile(id: 'u1', username: 'oliver', email: 'oliver@example.com');

  @override
  Future<UserProfile> getUser(String userId) async => profileToReturn;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeEventService implements EventService {
  List<AppEvent> eventsToReturn = [];
  List<AppEvent> notificationsToReturn = [];
  bool markAllCalled = false;
  String? lastMarkedReadId;

  @override
  Future<List<AppEvent>> listEvents(String token, {int limit = 200}) async => eventsToReturn;

  @override
  Future<List<AppEvent>> listNotifications(String token, {int limit = 50}) async => notificationsToReturn;

  @override
  Future<int> getUnreadCount(String token) async => notificationsToReturn.where((n) => !n.isRead).length;

  @override
  Future<void> markNotificationRead(String token, String eventId) async {
    lastMarkedReadId = eventId;
  }

  @override
  Future<void> markAllNotificationsRead(String token) async {
    markAllCalled = true;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

// A syntactically valid (unsigned) JWT with the given subject - WebShellScreen decodes this
// client-side to know which user id to fetch its own profile for (same helper as
// map_screen_test.dart).
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({'alg': 'HS256'})}.${segment({'sub': userId})}.sig';
}

AppEvent _event(String id, String kind, String text, {bool isNotification = false, bool isRead = true}) => AppEvent(
  id: id,
  kind: kind,
  displayText: text,
  isNotification: isNotification,
  isRead: isRead,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late _FakeWaypointService waypointService;
  late _FakeFriendsService friendsService;
  late _FakeBirdService birdService;
  late _FakeHubService hubService;
  late _FakeProfileService profileService;
  late _FakeEventService eventService;
  late AuthState authState;

  setUp(() {
    waypointService = _FakeWaypointService();
    friendsService = _FakeFriendsService();
    birdService = _FakeBirdService();
    hubService = _FakeHubService();
    profileService = _FakeProfileService();
    eventService = _FakeEventService();
    authState = AuthState()..login(_fakeJwtFor('u1'));
  });

  // This shell is desktop/web-only (kIsWeb-gated) and its 1440x900 design reference assumes
  // a real desktop window, not a phone-sized default test surface - a narrower default
  // viewport makes several rows overflow even though the real, intended usage never sees
  // that width.
  void setDesktopSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildShell() => MaterialApp(
    theme: croTheme,
    home: WebShellScreen(
      authState: authState,
      waypointService: waypointService,
      friendsService: friendsService,
      birdService: birdService,
      hubService: hubService,
      profileService: profileService,
      eventService: eventService,
    ),
  );

  testWidgets('shows a loading indicator, then the shell once data resolves', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(buildShell());
    expect(find.byKey(const Key('webShellLoading')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webShellLoading')), findsNothing);
    expect(find.byKey(const Key('webNavMap')), findsOneWidget);
    expect(find.byKey(const Key('yourBirdsDock')), findsOneWidget);
    expect(find.byKey(const Key('webContextPanel')), findsOneWidget);
  });

  testWidgets('shows an error state with Retry when loading fails', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: WebShellScreen(
        authState: authState,
        waypointService: waypointService,
        friendsService: friendsService,
        birdService: _ThrowingBirdService(),
        hubService: hubService,
        profileService: profileService,
        eventService: eventService,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webShellError')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('nests/friends nav badges reflect delivered-unread birds and incoming requests', (tester) async {
    setDesktopSize(tester);
    waypointService.waypointsToReturn = [
      Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93),
    ];
    birdService.birdsToReturn = [
      Bird(id: 'b1', userId: 'u1', name: 'Percy', currentNestId: 'n1', isTraveling: false, type: 'Cro', isRead: false),
    ];
    friendsService.incomingToReturn = [FriendRequest(userId: 'u2', username: 'mia')];

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('railBadge_Nests')), findsOneWidget);
    expect(find.byKey(const Key('railBadge_Friends')), findsOneWidget);
  });

  testWidgets('switching nav items renders the corresponding placeholder', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNavNests')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webPlaceholder_Nests')), findsOneWidget);
  });

  testWidgets('tapping an own nest marker opens the nest panel', (tester) async {
    setDesktopSize(tester);
    waypointService.waypointsToReturn = [
      Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93),
    ];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.text('Journey log'), findsOneWidget);
    await tester.tap(find.byKey(const Key('webOwnNestMarker_n1')));
    await tester.pumpAndSettle();

    expect(find.text('Your nest'), findsOneWidget);
    expect(find.text('Journey log'), findsNothing);

    await tester.tap(find.byKey(const Key('webPanelClose')));
    await tester.pumpAndSettle();
    expect(find.text('Journey log'), findsOneWidget);
  });

  testWidgets('journey log lists fetched events', (tester) async {
    setDesktopSize(tester);
    eventService.eventsToReturn = [_event('e1', EventKind.birdJoinedFlock, 'Percy joined your flock')];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.text('Percy joined your flock'), findsOneWidget);
  });

  testWidgets('bell shows unread count and mark-all-read clears the dropdown badges', (tester) async {
    setDesktopSize(tester);
    eventService.notificationsToReturn = [
      _event('n1', EventKind.friendRequestAccepted, 'mia accepted your friend request', isNotification: true, isRead: false),
    ];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webNotificationBadge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();
    expect(find.text('mia accepted your friend request'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webMarkAllReadButton')));
    await tester.pumpAndSettle();
    expect(eventService.markAllCalled, isTrue);
  });
}

class _ThrowingBirdService implements BirdService {
  @override
  Future<List<Bird>> listBirds(String token) async => throw BirdException('boom');

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}
