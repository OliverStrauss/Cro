import 'dart:async';
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
import 'package:cro_app/utils/color_utils.dart';
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
  List<Friend> friendsToReturn = [];

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => friendWaypointsToReturn;

  @override
  Future<List<FriendBird>> getFriendsBirds(String token) async => friendsBirdsToReturn;

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => incomingToReturn;

  @override
  Future<List<Friend>> getFriends(String token) async => friendsToReturn;

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
  Map<String, List<Bird>> residentsByNestId = {};
  String? lastMarkedViewedBirdId;

  @override
  Future<List<Bird>> listBirds(String token) async => birdsToReturn;

  @override
  Future<List<Bird>> getNestResidents(String token, String nestId) async => residentsByNestId[nestId] ?? [];

  @override
  Future<void> markBirdViewed(String token, String birdId) async {
    lastMarkedViewedBirdId = birdId;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}

class _FakeHubService implements HubService {
  List<Hub> hubsToReturn = [];
  Map<String, int> unreadCountsToReturn = {};
  String? lastMarkedReadHubId;

  @override
  Future<List<Hub>> listHubs(String token) async => hubsToReturn;

  @override
  Future<List<HubMessage>> listMessages(String token, String hubId) async => [];

  @override
  Future<Map<String, int>> getUnreadCounts(String token) async => unreadCountsToReturn;

  @override
  Future<void> markHubRead(String token, String hubId) async {
    lastMarkedReadHubId = hubId;
  }

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
  // When set, listNotifications() hangs on this instead of resolving immediately - lets a
  // test hold one poll's response in flight to deterministically race it against a
  // concurrent mark-read mutation (see the poll-race regression test below).
  Completer<List<AppEvent>>? pendingNotifications;

  @override
  Future<List<AppEvent>> listEvents(String token, {int limit = 200}) async => eventsToReturn;

  @override
  Future<List<AppEvent>> listNotifications(String token, {int limit = 50}) {
    final pending = pendingNotifications;
    return pending != null ? pending.future : Future.value(notificationsToReturn);
  }

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

AppEvent _event(
  String id,
  String kind,
  String text, {
  bool isNotification = false,
  bool isRead = true,
  String? sourceUserId,
  String? targetType,
}) => AppEvent(
  id: id,
  kind: kind,
  displayText: text,
  isNotification: isNotification,
  isRead: isRead,
  createdAt: DateTime(2026, 1, 1),
  sourceUserId: sourceUserId,
  targetType: targetType,
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
    // The right panel only mounts once a nest/hub/bird is selected - with nothing selected
    // it's absent entirely so the map reclaims the full width.
    expect(find.byKey(const Key('webContextPanel')), findsNothing);
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
    birdService.residentsByNestId = {
      'n1': [Bird(id: 'b1', userId: 'u1', name: 'Percy', currentNestId: 'n1', isTraveling: false, type: 'Cro', isRead: false)],
    };
    friendsService.incomingToReturn = [FriendRequest(userId: 'u2', username: 'mia')];

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('railBadge_Nests')), findsOneWidget);
    expect(find.byKey(const Key('railBadge_Friends')), findsOneWidget);
  });

  testWidgets('switching nav items renders the corresponding screen', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNavNests')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webNestsScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webNavHubs')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webHubsScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webNavFriends')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webFriendsScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webNavYou')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webYouScreen')), findsOneWidget);
  });

  testWidgets('tapping an own nest marker opens the nest panel, and closing it unmounts the panel', (tester) async {
    setDesktopSize(tester);
    waypointService.waypointsToReturn = [
      Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93),
    ];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webContextPanel')), findsNothing);
    await tester.tap(find.byKey(const Key('webOwnNestMarker_n1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webContextPanel')), findsOneWidget);
    expect(find.text('Your nest'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webPanelClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webContextPanel')), findsNothing);
  });

  testWidgets('tapping an unread Hub marker opens its panel and marks it read', (tester) async {
    setDesktopSize(tester);
    hubService.hubsToReturn = [
      // No own nests are set up in this test, so the map defaults to its Ames, Iowa center
      // (see WebMapScreen._amesCenter) - place the hub there so it's actually on screen.
      Hub(id: 'h1', name: 'Lighthouse', latitude: 42.0308, longitude: -93.6319, status: 'Approved', createdByUserId: 'admin'),
    ];
    hubService.unreadCountsToReturn = {'h1': 3};
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webHubUnreadBadge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webHubMarker_h1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webContextPanel')), findsOneWidget);
    expect(hubService.lastMarkedReadHubId, 'h1');
    // Optimistically cleared locally, without waiting on the next poll.
    expect(find.byKey(const Key('webHubUnreadBadge')), findsNothing);
  });

  testWidgets("tapping a friend's public bird marker opens its panel and marks it viewed", (tester) async {
    setDesktopSize(tester);
    waypointService.waypointsToReturn = [
      Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 1.0, longitude: 2.0),
    ];
    friendsService.friendWaypointsToReturn = [
      Waypoint(
        id: 'f1',
        userId: 'u2',
        name: "Mia's Cabin",
        latitude: 1.002,
        longitude: 2.002,
        username: 'mia',
        color: '#E53935',
      ),
    ];
    friendsService.friendsBirdsToReturn = [
      FriendBird(
        id: 'fb1',
        userId: 'u2',
        username: 'mia',
        color: '#E53935',
        name: 'Fen',
        type: 'Cro',
        nestFromId: 'f1',
        nestToId: 'n1',
        departedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 1)),
        isPublic: true,
        content: 'On my way',
      ),
    ];
    // Not pumpAndSettle: a traveling bird starts the map's repeating bob animation, which
    // never "settles" - bounded pumps instead, same convention map_screen_test.dart uses for
    // bird marker taps.
    await tester.pumpWidget(buildShell());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('webContextPanel')), findsNothing);
    await tester.tap(find.byKey(const Key('webBirdMarker_fb1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('webContextPanel')), findsOneWidget);
    expect(find.text('On my way'), findsOneWidget);
    expect(birdService.lastMarkedViewedBirdId, 'fb1');
  });

  testWidgets('journey log button opens a popup listing fetched events', (tester) async {
    setDesktopSize(tester);
    eventService.eventsToReturn = [_event('e1', EventKind.birdJoinedFlock, 'Percy joined your flock')];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.text('Percy joined your flock'), findsNothing);
    await tester.tap(find.byKey(const Key('webJourneyLogButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webJourneyLogDropdown')), findsOneWidget);
    expect(find.text('Percy joined your flock'), findsOneWidget);
    // Regression check: the popup must size to its own content (380px), not stretch to fill
    // the whole screen - it lives in an Overlay entry, whose root is forced to fill the
    // screen unless explicitly wrapped to avoid that (see FloatingActionsCluster's
    // OverlayEntry builders).
    expect(tester.getSize(find.byKey(const Key('webJourneyLogDropdown'))).width, 380);

    await tester.tap(find.byKey(const Key('webJourneyLogClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webJourneyLogDropdown')), findsNothing);
  });

  testWidgets('the journey log popup and the notifications dropdown are mutually exclusive', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webJourneyLogButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webJourneyLogDropdown')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webJourneyLogDropdown')), findsNothing);
    expect(find.byKey(const Key('webNotificationsDropdown')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webJourneyLogButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webNotificationsDropdown')), findsNothing);
    expect(find.byKey(const Key('webJourneyLogDropdown')), findsOneWidget);
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

  testWidgets(
    'a poll response already in flight when Mark all read runs does not revert the badge, and later arrivals show only their own count',
    (tester) async {
      setDesktopSize(tester);
      final oldUnread = List.generate(
        10,
        (i) => _event('old$i', EventKind.birdArrivedAtYourNest, 'Old $i arrived', isNotification: true, isRead: false),
      );
      eventService.notificationsToReturn = oldUnread;
      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('webNotificationBadge')), matching: find.text('10')), findsOneWidget);

      // Hold the next poll's GET /notifications response in flight, as if it had already
      // been sent before the mark-all-read tap below.
      eventService.pendingNotifications = Completer<List<AppEvent>>();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.byKey(const Key('webNotificationBell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('webMarkAllReadButton')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('webNotificationBadge')), findsNothing);

      // Let that stale, pre-mark-read response land now - it must not resurrect the old
      // unread count.
      eventService.pendingNotifications!.complete(oldUnread);
      eventService.pendingNotifications = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('webNotificationBadge')), findsNothing);

      // Two genuinely new notifications arrive - the badge should show just those, not the
      // old count stacked back on top of them.
      eventService.notificationsToReturn = [
        for (final n in oldUnread) _event(n.id, n.kind, n.displayText, isNotification: true),
        _event('new0', EventKind.birdArrivedAtYourNest, 'New 0 arrived', isNotification: true, isRead: false),
        _event('new1', EventKind.birdArrivedAtYourNest, 'New 1 arrived', isNotification: true, isRead: false),
      ];
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('webNotificationBadge')), matching: find.text('2')), findsOneWidget);
    },
  );

  testWidgets('empty notifications dropdown is just its header - no placeholder, no mark-all-read', (tester) async {
    setDesktopSize(tester);
    eventService.notificationsToReturn = [];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webNotificationsDropdown')), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byKey(const Key('webMarkAllReadButton')), findsNothing);
    expect(find.text('Nothing yet'), findsNothing);
  });

  testWidgets('notification rows show a kind-tinted glyph and a relative-time line', (tester) async {
    setDesktopSize(tester);
    eventService.notificationsToReturn = [
      AppEvent(
        id: 'n2',
        kind: EventKind.birdArrivedAtYourNest,
        displayText: 'Juniper arrived at your Home Roost',
        isNotification: true,
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
    ];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();

    expect(find.text('Juniper arrived at your Home Roost'), findsOneWidget);
    expect(find.text('4 minutes ago'), findsOneWidget);
    expect(find.byIcon(Icons.flutter_dash), findsOneWidget);
    // Regression check: see the matching note on the journey log popup above.
    expect(tester.getSize(find.byKey(const Key('webNotificationsDropdown'))).width, 372);
  });

  testWidgets('a notification with a resolvable sender is tinted with that friend\'s color, and its target gets a label chip', (
    tester,
  ) async {
    setDesktopSize(tester);
    friendsService.friendsToReturn = [Friend(userId: 'u2', username: 'oliver', color: '#1E88E5')];
    eventService.notificationsToReturn = [
      _event(
        'n3',
        EventKind.birdArrivedAtYourNest,
        'Juniper arrived at your Home Roost',
        isNotification: true,
        isRead: false,
        sourceUserId: 'u2',
        targetType: 'Nest',
      ),
    ];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();

    expect(find.text('Your nest'), findsOneWidget);
    // The 34x34 avatar circle, not the smaller 8x8 unread dot also rendered in this row -
    // both are circular Containers.
    final avatarContainers = tester
        .widgetList<Container>(find.descendant(of: find.byKey(const Key('webNotification_n3')), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).shape == BoxShape.circle && c.constraints?.maxWidth == 34);
    expect((avatarContainers.single.decoration as BoxDecoration).color, hexToColor('#1E88E5'));
  });

  testWidgets('a pending incoming friend request shows in the notification feed and routes to Friends when tapped', (
    tester,
  ) async {
    setDesktopSize(tester);
    friendsService.incomingToReturn = [FriendRequest(userId: 'u2', username: 'mia')];
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webNotificationBell')));
    await tester.pumpAndSettle();

    expect(find.text('mia wants to be friends'), findsOneWidget);
    expect(find.text('Friend request'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webFriendRequestNotification_u2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webFriendsScreen')), findsOneWidget);
  });
}

class _ThrowingBirdService implements BirdService {
  @override
  Future<List<Bird>> listBirds(String token) async => throw BirdException('boom');

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebShellScreen');
}
