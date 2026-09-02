import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_bird.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/hub_category.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_map_screen.dart';
import 'package:cro_app/widgets/avatar_with_fallback.dart';

void main() {
  final ownNest = Waypoint(id: 'w1', userId: 'u1', name: 'Home', latitude: 1.0, longitude: 2.0);
  final friendNest = Waypoint(
    id: 'fw1',
    userId: 'friend1',
    name: "Friend's Nest",
    latitude: 1.002,
    longitude: 2.002,
    username: 'friendo',
    color: '#1E88E5',
  );

  FriendBird makeFriendBird({required String id, required bool isPublic, bool hasViewed = false}) => FriendBird(
    id: id,
    userId: 'friend1',
    username: 'friendo',
    color: '#1E88E5',
    name: 'Fen',
    type: 'Cro',
    nestFromId: 'fw1',
    nestToId: 'w1',
    departedAt: DateTime.now().subtract(const Duration(minutes: 1)),
    estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 1)),
    isPublic: isPublic,
    content: isPublic ? 'hello' : null,
    hasViewed: hasViewed,
  );

  Widget buildMap({
    List<FriendBird> friendsBirds = const [],
    List<Friend> friends = const [],
    String? selectedBirdId,
    ValueChanged<FriendBird>? onSelectFriendBird,
    bool isAdmin = false,
    bool addingHub = false,
    VoidCallback? onCancelAddHub,
    List<Hub> hubs = const [],
    Map<String, int> hubUnreadCounts = const {},
    Map<String, List<Bird>> nestResidentsByNestId = const {},
    String? selectedHubId,
    ValueChanged<Hub>? onSelectHub,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebMapScreen(
          ownNests: [ownNest],
          friendWaypoints: [friendNest],
          birds: const [],
          friendsBirds: friendsBirds,
          hubs: hubs,
          friends: friends,
          hubUnreadCounts: hubUnreadCounts,
          nestResidentsByNestId: nestResidentsByNestId,
          selectedNestId: null,
          selectedHubId: selectedHubId,
          selectedBirdId: selectedBirdId,
          bottomInset: 132,
          onSelectNest: (_) {},
          onSelectHub: onSelectHub ?? (_) {},
          onSelectBird: (_) {},
          onSelectFriendBird: onSelectFriendBird ?? (_) {},
          isAdmin: isAdmin,
          addingHub: addingHub,
          onCancelAddHub: onCancelAddHub,
        ),
      ),
    );
  }

  testWidgets("a friend's public, unread bird marker shows an amber public badge and is tappable", (tester) async {
    FriendBird? tapped;
    final bird = makeFriendBird(id: 'fb1', isPublic: true);
    await tester.pumpWidget(buildMap(friendsBirds: [bird], onSelectFriendBird: (b) => tapped = b));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('webPublicBirdBadge')), findsOneWidget);
    final badge = tester.widget<Container>(find.byKey(const Key('webPublicBirdBadge')));
    final decoration = badge.decoration as BoxDecoration;
    expect(decoration.color, CroColors.deliveryAmber);

    await tester.tap(find.byKey(const Key('webBirdMarker_fb1')));
    expect(tapped?.id, 'fb1');
  });

  testWidgets("a friend's public, already-viewed bird marker shows a grey public badge", (tester) async {
    final bird = makeFriendBird(id: 'fb1', isPublic: true, hasViewed: true);
    await tester.pumpWidget(buildMap(friendsBirds: [bird]));
    await tester.pump();
    await tester.pump();

    final badge = tester.widget<Container>(find.byKey(const Key('webPublicBirdBadge')));
    final decoration = badge.decoration as BoxDecoration;
    expect(decoration.color, CroColors.fog);
  });

  testWidgets("a friend's private bird marker has no badge and is not tappable", (tester) async {
    FriendBird? tapped;
    final bird = makeFriendBird(id: 'fb1', isPublic: false);
    await tester.pumpWidget(buildMap(friendsBirds: [bird], onSelectFriendBird: (b) => tapped = b));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('webPublicBirdBadge')), findsNothing);

    final gesture = tester.widget<GestureDetector>(
      find.ancestor(of: find.byKey(const Key('webBirdMarkerDot_fb1')), matching: find.byType(GestureDetector)).first,
    );
    expect(gesture.onTap, isNull);

    await tester.tap(find.byKey(const Key('webBirdMarker_fb1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapped, isNull);
  });

  testWidgets('the currently-followed bird gets a glow, others do not', (tester) async {
    final bird = makeFriendBird(id: 'fb1', isPublic: true);
    await tester.pumpWidget(buildMap(friendsBirds: [bird], selectedBirdId: 'fb1'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('webBirdMarkerGlow')), findsOneWidget);
  });

  testWidgets('no glow when no bird is selected', (tester) async {
    final bird = makeFriendBird(id: 'fb1', isPublic: true);
    await tester.pumpWidget(buildMap(friendsBirds: [bird]));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('webBirdMarkerGlow')), findsNothing);
  });

  testWidgets('addingHub banner reads "place" for an admin and "suggest" otherwise', (tester) async {
    await tester.pumpWidget(buildMap(addingHub: true, isAdmin: true));
    expect(find.text('Click anywhere on the map to place your new Hub'), findsOneWidget);

    await tester.pumpWidget(buildMap(addingHub: true, isAdmin: false));
    expect(find.text('Click anywhere on the map to suggest a Hub location'), findsOneWidget);
  });

  testWidgets('no addingHub banner when not arming a Hub placement', (tester) async {
    await tester.pumpWidget(buildMap());
    expect(find.byKey(const Key('webAddHubBanner')), findsNothing);
  });

  testWidgets('cancelling the addingHub banner calls onCancelAddHub', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(buildMap(addingHub: true, onCancelAddHub: () => cancelled = true));

    await tester.tap(find.byKey(const Key('webCancelAddHub')));
    expect(cancelled, isTrue);
  });

  testWidgets('Trails legend lists your trails, each friend, then Hubs', (tester) async {
    final friends = [
      Friend(userId: 'u2', username: 'mia_c', color: '#E8714A'),
      Friend(userId: 'u3', username: 'sam_r', color: '#4FA97C'),
    ];
    await tester.pumpWidget(buildMap(friends: friends));

    expect(find.byKey(const Key('webMapTrailsLegend')), findsOneWidget);
    expect(find.text('Your trails'), findsOneWidget);
    expect(find.text('mia_c'), findsOneWidget);
    expect(find.text('sam_r'), findsOneWidget);
    expect(find.text('Hubs'), findsOneWidget);
  });

  // Well clear of ownNest (1.0, 2.0) and friendNest (1.002, 2.002) - those two sit close
  // enough together that a wider nest marker pill can otherwise occlude a hub dot tapped in
  // the same test.
  final hub = Hub(id: 'h1', name: 'Lighthouse', latitude: 1.05, longitude: 2.05, status: 'Approved', createdByUserId: 'admin');

  testWidgets('a Hub marker shows its unread count badge only when it has unread messages', (tester) async {
    await tester.pumpWidget(buildMap(hubs: [hub], hubUnreadCounts: {'h1': 2}));
    await tester.pump();
    expect(find.byKey(const Key('webHubUnreadBadge')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('webHubUnreadBadge')), matching: find.text('2')), findsOneWidget);

    await tester.pumpWidget(buildMap(hubs: [hub], hubUnreadCounts: {'h1': 0}));
    await tester.pump();
    expect(find.byKey(const Key('webHubUnreadBadge')), findsNothing);

    await tester.pumpWidget(buildMap(hubs: [hub]));
    await tester.pump();
    expect(find.byKey(const Key('webHubUnreadBadge')), findsNothing);
  });

  testWidgets("an own nest marker shows its unread count badge only when it has unread residents", (tester) async {
    Bird makeResident({required String id, required bool isRead}) => Bird(
      id: id,
      userId: 'u1',
      name: 'Fen',
      currentNestId: ownNest.id,
      isTraveling: false,
      type: 'Cro',
      isRead: isRead,
    );

    await tester.pumpWidget(buildMap(
      nestResidentsByNestId: {
        ownNest.id: [makeResident(id: 'b1', isRead: false), makeResident(id: 'b2', isRead: false)],
      },
    ));
    await tester.pump();
    expect(find.byKey(Key('webNestUnreadBadge_${ownNest.id}')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(Key('webNestUnreadBadge_${ownNest.id}')), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.pumpWidget(buildMap(
      nestResidentsByNestId: {
        ownNest.id: [makeResident(id: 'b1', isRead: true)],
      },
    ));
    await tester.pump();
    expect(find.byKey(Key('webNestUnreadBadge_${ownNest.id}')), findsNothing);

    await tester.pumpWidget(buildMap());
    await tester.pump();
    expect(find.byKey(Key('webNestUnreadBadge_${ownNest.id}')), findsNothing);
  });

  testWidgets('a Hub marker shows its category icon with no photo, or the approved photo when set', (tester) async {
    await tester.pumpWidget(buildMap(hubs: [hub]));
    await tester.pump();

    expect(find.byIcon(HubCategory.iconFor(hub.category)), findsOneWidget);
    var avatar = tester.widget<AvatarWithFallback>(find.byType(AvatarWithFallback));
    expect(avatar.imageUrl, isNull);

    final photoHub = Hub(
      id: 'h1',
      name: 'Lighthouse',
      latitude: 1.05,
      longitude: 2.05,
      status: 'Approved',
      createdByUserId: 'admin',
      profilePictureUrl: 'https://example.com/lighthouse.jpg',
    );
    await tester.pumpWidget(buildMap(hubs: [photoHub]));
    await tester.pump();

    avatar = tester.widget<AvatarWithFallback>(find.byType(AvatarWithFallback));
    expect(avatar.imageUrl, 'https://example.com/lighthouse.jpg');
  });

  testWidgets('tapping a Hub marker calls onSelectHub, and selecting it glows the marker', (tester) async {
    Hub? tapped;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildMap(hubs: [hub], onSelectHub: (h) => tapped = h));
    await tester.pump();

    expect(find.byKey(const Key('webHubMarkerGlow')), findsNothing);
    await tester.tap(find.byKey(const Key('webHubMarker_h1')));
    expect(tapped?.id, 'h1');

    await tester.pumpWidget(buildMap(hubs: [hub], selectedHubId: 'h1'));
    await tester.pump();
    expect(find.byKey(const Key('webHubMarkerGlow')), findsOneWidget);
  });
}
