import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/waypoint_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_nests_screen.dart';

class _FakeWaypointService implements WaypointService {
  Waypoint? lastUpdated;
  String? lastDeletedId;

  @override
  Future<Waypoint> updateWaypoint(
    String token,
    String id, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final updated = Waypoint(id: id, userId: 'u1', name: name, latitude: latitude, longitude: longitude);
    lastUpdated = updated;
    return updated;
  }

  @override
  Future<void> deleteWaypoint(String token, String id) async {
    lastDeletedId = id;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebNestsScreen');
}

void main() {
  final ownNest = Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42.1234, longitude: -93.5678);
  final friendNest = Waypoint(id: 'f1', userId: 'u2', name: "Mia's Cabin", latitude: 43, longitude: -92, username: 'mia', color: '#E53935');

  late _FakeWaypointService waypointService;
  late AuthState authState;

  setUp(() {
    waypointService = _FakeWaypointService();
    authState = AuthState()..login('a.b.c');
  });

  Widget build({
    List<Waypoint> ownNests = const [],
    List<Waypoint> friendWaypoints = const [],
    Map<String, List<Bird>> residents = const {},
    VoidCallback? onStartAddNest,
    ValueChanged<Waypoint>? onSelectNest,
    VoidCallback? onDataChanged,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebNestsScreen(
          ownNests: ownNests,
          friendWaypoints: friendWaypoints,
          nestResidentsByNestId: residents,
          selectedNestId: null,
          onSelectNest: onSelectNest ?? (_) {},
          onStartAddNest: onStartAddNest ?? () {},
          authState: authState,
          waypointService: waypointService,
          onDataChanged: onDataChanged ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows own and friend nests, and an empty state when there are none', (tester) async {
    await tester.pumpWidget(build());
    expect(find.byKey(const Key('noOwnNestsMessage')), findsOneWidget);

    await tester.pumpWidget(build(ownNests: [ownNest], friendWaypoints: [friendNest]));
    expect(find.byKey(const Key('webNestCard_n1')), findsOneWidget);
    expect(find.byKey(const Key('webFriendNestCard_f1')), findsOneWidget);
    expect(find.text('Home Roost'), findsOneWidget);
    expect(find.text("Mia's Cabin"), findsOneWidget);
  });

  testWidgets('shows a waiting badge only when a resident bird is unread', (tester) async {
    await tester.pumpWidget(build(
      ownNests: [ownNest],
      residents: {
        'n1': [Bird(id: 'b1', userId: 'u2', name: 'Juniper', currentNestId: 'n1', isTraveling: false, type: 'Cro', isRead: false)],
      },
    ));
    expect(find.byKey(const Key('webNestWaitingBadge_n1')), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
  });

  testWidgets('tapping "+ Add a nest" calls onStartAddNest', (tester) async {
    var called = false;
    await tester.pumpWidget(build(onStartAddNest: () => called = true));
    await tester.tap(find.byKey(const Key('webAddNestButton')));
    expect(called, isTrue);
  });

  testWidgets('the add-nest button relabels to "Move nest" once the user already has one', (tester) async {
    // 05_web_ui_updates.md item 6: no count line, no "already have a nest" note - the button
    // is unconditional; WebShellScreen._placeNest now relocates the existing nest instead of
    // erroring, once the user taps the map.
    var called = false;
    await tester.pumpWidget(build(ownNests: [ownNest], onStartAddNest: () => called = true));
    expect(find.text('You already have a nest'), findsNothing);
    expect(find.text('+ Add a nest'), findsNothing);
    expect(find.text('Move nest'), findsOneWidget);
    await tester.tap(find.byKey(const Key('webAddNestButton')));
    expect(called, isTrue);
  });

  testWidgets('delete requires two taps to confirm', (tester) async {
    await tester.pumpWidget(build(ownNests: [ownNest]));

    await tester.tap(find.byKey(const Key('webDeleteNestButton_n1')));
    await tester.pump();
    expect(find.text('Confirm?'), findsOneWidget);
    expect(waypointService.lastDeletedId, isNull);

    await tester.tap(find.byKey(const Key('webDeleteNestButton_n1')));
    await tester.pump();
    expect(waypointService.lastDeletedId, 'n1');
  });

  testWidgets('tapping a nest card calls onSelectNest', (tester) async {
    Waypoint? selected;
    await tester.pumpWidget(build(ownNests: [ownNest], onSelectNest: (n) => selected = n));
    await tester.tap(find.byKey(const Key('webNestCard_n1')));
    expect(selected?.id, 'n1');
  });
}
