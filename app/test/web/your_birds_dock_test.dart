import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/state/web_shell_controller.dart';
import 'package:cro_app/web/widgets/dock_bird_card.dart';
import 'package:cro_app/web/widgets/your_birds_dock.dart';

void main() {
  final ownNest = Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93);
  final friendNest = Waypoint(
    id: 'f1',
    userId: 'u2',
    name: "Mia's Cabin",
    latitude: 43,
    longitude: -92,
    username: 'mia',
    color: '#E53935',
  );
  final hub = Hub(id: 'h1', name: 'Lighthouse', latitude: 44, longitude: -91, status: 'Approved', createdByUserId: 'admin');

  Widget buildDock({
    required List<Bird> birds,
    DockFilter filter = DockFilter.all,
    bool expanded = false,
    bool hidden = false,
    VoidCallback? onHide,
    VoidCallback? onShow,
    ValueChanged<Bird>? onBirdTap,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: YourBirdsDock(
          birds: birds,
          ownNests: [ownNest],
          friendWaypoints: [friendNest],
          hubs: [hub],
          filter: filter,
          onFilterChanged: (_) {},
          expanded: expanded,
          onToggleExpanded: () {},
          hidden: hidden,
          onHide: onHide ?? () {},
          onShow: onShow ?? () {},
          onBirdTap: onBirdTap ?? (_) {},
          onComposePressed: () {},
        ),
      ),
    );
  }

  testWidgets('every bird in the flock shows a card regardless of state', (tester) async {
    final birds = [
      Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Cro'),
      Bird(id: 'b2', userId: 'u1', name: 'Percy', currentNestId: 'f1', isTraveling: false, type: 'Cro'),
      Bird(id: 'b3', userId: 'u1', name: 'Fen', currentNestId: 'h1', isTraveling: false, type: 'Cro'),
      Bird(
        id: 'b4',
        userId: 'u1',
        name: 'Juniper',
        isTraveling: true,
        nestFromId: 'n1',
        nestToId: 'f1',
        type: 'Cro',
        departedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 50)),
      ),
    ];

    await tester.pumpWidget(buildDock(birds: birds));
    await tester.pump();

    expect(find.byKey(const Key('dockCard_b1')), findsOneWidget);
    expect(find.byKey(const Key('dockCard_b2')), findsOneWidget);
    expect(find.byKey(const Key('dockCard_b3')), findsOneWidget);
    expect(find.byKey(const Key('dockCard_b4')), findsOneWidget);
    // "Home"/"Away" also appear as filter-chip labels, so state labels are checked via
    // their card, not a bare text lookup.
    expect(find.text('At a hub'), findsOneWidget);
    expect(find.text('In flight'), findsOneWidget);
  });

  testWidgets('a bird pointing at an unknown nest/hub is dropped, not crashed on', (tester) async {
    final birds = [
      Bird(id: 'stale', userId: 'u1', name: 'Ghost', currentNestId: 'does-not-exist', isTraveling: false, type: 'Cro'),
    ];
    await tester.pumpWidget(buildDock(birds: birds));
    await tester.pump();

    expect(find.byKey(const Key('dockCard_stale')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Home filter hides everything except home birds', (tester) async {
    final birds = [
      Bird(id: 'home1', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Cro'),
      Bird(id: 'away1', userId: 'u1', name: 'Percy', currentNestId: 'f1', isTraveling: false, type: 'Cro'),
    ];
    await tester.pumpWidget(buildDock(birds: birds, filter: DockFilter.home));
    await tester.pump();

    expect(find.byKey(const Key('dockCard_home1')), findsOneWidget);
    expect(find.byKey(const Key('dockCard_away1')), findsNothing);
  });

  testWidgets('tapping a card invokes onBirdTap with that bird', (tester) async {
    Bird? tapped;
    final bird = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(buildDock(birds: [bird], onBirdTap: (b) => tapped = b));
    await tester.pump();

    await tester.tap(find.byKey(const Key('dockCard_b1')));
    expect(tapped?.id, 'b1');
  });

  testWidgets('expanded mode adds the type/description line without crashing', (tester) async {
    final bird = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Parrot');
    await tester.pumpWidget(buildDock(birds: [bird], expanded: true));
    await tester.pump();

    expect(find.textContaining('Audio clip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the trailing "send a new bird" card is always present', (tester) async {
    await tester.pumpWidget(buildDock(birds: []));
    await tester.pump();
    expect(find.byKey(const Key('dockAddBirdCard')), findsOneWidget);
  });

  testWidgets('tapping Hide swaps the dock for the collapsed Show pill', (tester) async {
    var hidden = false;
    await tester.pumpWidget(buildDock(birds: [], onHide: () => hidden = true));
    await tester.pump();

    expect(find.byKey(const Key('yourBirdsDock')), findsOneWidget);
    expect(find.byKey(const Key('dockShowPill')), findsNothing);

    await tester.tap(find.byKey(const Key('dockHideButton')));
    expect(hidden, isTrue);
  });

  testWidgets('hidden shows only the summary pill, and tapping it calls onShow', (tester) async {
    var shown = false;
    final birds = [
      Bird(id: 'home1', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Cro'),
    ];
    await tester.pumpWidget(buildDock(birds: birds, hidden: true, onShow: () => shown = true));
    await tester.pump();

    expect(find.byKey(const Key('yourBirdsDock')), findsNothing);
    expect(find.byKey(const Key('dockHideButton')), findsNothing);
    expect(find.byKey(const Key('dockShowPill')), findsOneWidget);
    expect(find.textContaining('1 home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dockShowPill')));
    expect(shown, isTrue);
  });

  testWidgets(
    'cards are sorted home, away, hub, flying-to-a-nest, flying-to-a-hub regardless of input order',
    (tester) async {
      // Wide enough that all 5 cards actually lay out within the horizontal ListView's
      // viewport - at the default (narrow) test size, cards past the visible edge are never
      // built, so find.byType wouldn't see them at all.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final birds = [
        // Deliberately scrambled input order - the dock must reorder this itself.
        Bird(
          id: 'flightHub',
          userId: 'u1',
          name: 'Fen',
          isTraveling: true,
          nestFromId: 'n1',
          nestToId: 'h1',
          type: 'Cro',
          departedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
        Bird(
          id: 'flightNest',
          userId: 'u1',
          name: 'Juniper',
          isTraveling: true,
          nestFromId: 'n1',
          nestToId: 'f1',
          type: 'Cro',
          departedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
        Bird(id: 'hub', userId: 'u1', name: 'Willa', currentNestId: 'h1', isTraveling: false, type: 'Cro'),
        Bird(id: 'away', userId: 'u1', name: 'Percy', currentNestId: 'f1', isTraveling: false, type: 'Cro'),
        Bird(id: 'home', userId: 'u1', name: 'Otto', currentNestId: 'n1', isTraveling: false, type: 'Cro'),
      ];

      await tester.pumpWidget(buildDock(birds: birds));
      await tester.pump();

      final order = tester.widgetList<DockBirdCard>(find.byType(DockBirdCard)).map((c) => c.view.bird.id).toList();
      expect(order, ['home', 'away', 'hub', 'flightNest', 'flightHub']);
    },
  );
}
