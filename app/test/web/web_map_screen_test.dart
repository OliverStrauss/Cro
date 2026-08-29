import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/friend_bird.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_map_screen.dart';

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
    String? selectedBirdId,
    ValueChanged<FriendBird>? onSelectFriendBird,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebMapScreen(
          ownNests: [ownNest],
          friendWaypoints: [friendNest],
          birds: const [],
          friendsBirds: friendsBirds,
          hubs: const <Hub>[],
          selectedNestId: null,
          selectedHubId: null,
          selectedBirdId: selectedBirdId,
          bottomInset: 132,
          filter: MapFilter.all,
          onFilterChanged: (_) {},
          onSelectNest: (_) {},
          onSelectHub: (_) {},
          onSelectBird: (_) {},
          onSelectFriendBird: onSelectFriendBird ?? (_) {},
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
}
