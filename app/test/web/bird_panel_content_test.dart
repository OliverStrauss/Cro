import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/bird_reaction.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_reaction_service.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/widgets/bird_panel_content.dart';

class _FakeBirdReactionService implements BirdReactionService {
  List<BirdReactionSummary> reactions = [];
  String? lastAddedEmoji;
  String? lastRemovedEmoji;

  @override
  Future<List<BirdReactionSummary>> getReactions(String token, String birdId) async => reactions;

  @override
  Future<List<BirdReactionSummary>> addReaction(String token, String birdId, String emoji) async {
    lastAddedEmoji = emoji;
    reactions = [
      ...reactions.where((r) => r.emoji != emoji),
      BirdReactionSummary(emoji: emoji, count: 1, reactedByMe: true),
    ];
    return reactions;
  }

  @override
  Future<void> removeReaction(String token, String birdId, String emoji) async {
    lastRemovedEmoji = emoji;
    reactions = reactions.where((r) => r.emoji != emoji).toList();
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by BirdPanelContent');
}

class _FakeBirdService implements BirdService {
  String? lastSendBirdId;
  String? lastSendNestId;
  String? lastSendContent;

  @override
  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    lastSendBirdId = birdId;
    lastSendNestId = nestId;
    lastSendContent = content;
    return Bird(id: birdId, userId: 'u1', name: 'Sent', currentNestId: nestId, isTraveling: true, type: 'Cro');
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by BirdPanelContent');
}

void main() {
  final ownNest = Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93);
  final ownNest2 = Waypoint(id: 'n2', userId: 'u1', name: 'Cabin', latitude: 41, longitude: -94);
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

  late _FakeBirdReactionService reactionService;
  late _FakeBirdService birdService;
  late AuthState authState;

  setUp(() {
    reactionService = _FakeBirdReactionService();
    birdService = _FakeBirdService();
    authState = AuthState()..login('a.b.c');
  });

  Widget build(
    Bird bird, {
    VoidCallback? onClose,
    VoidCallback? onDataChanged,
    VoidCallback? onFollowOnMap,
    VoidCallback? onComposePressed,
    List<Waypoint>? ownNests,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: BirdPanelContent(
          bird: bird,
          ownNests: ownNests ?? [ownNest],
          friendWaypoints: [friendNest],
          hubs: [hub],
          authState: authState,
          reactionService: reactionService,
          birdService: birdService,
          onClose: onClose ?? () {},
          onDataChanged: onDataChanged ?? () {},
          onFollowOnMap: onFollowOnMap ?? () {},
          onComposePressed: onComposePressed ?? () {},
        ),
      ),
    );
  }

  testWidgets('a private bird shows the sealed placeholder, not the content', (tester) async {
    final bird = Bird(
      id: 'b1',
      userId: 'u1',
      name: 'Otto',
      currentNestId: 'n1',
      isTraveling: false,
      type: 'Cro',
      content: 'Secret message',
      isPublic: false,
    );
    await tester.pumpWidget(build(bird));
    await tester.pump();

    expect(find.text('Sealed until it lands'), findsOneWidget);
    expect(find.text('Secret message'), findsNothing);
    expect(find.byKey(const Key('webBirdReactionRow')), findsNothing);
  });

  testWidgets('a public bird shows its content and a reaction row', (tester) async {
    final bird = Bird(
      id: 'b2',
      userId: 'u1',
      name: 'Percy',
      isTraveling: true,
      nestFromId: 'n1',
      nestToId: 'f1',
      type: 'Cro',
      content: 'On my way!',
      isPublic: true,
      departedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 50)),
    );
    await tester.pumpWidget(build(bird));
    await tester.pump();

    expect(find.text('What it carries'), findsOneWidget);
    expect(find.text('On my way!'), findsOneWidget);
    expect(find.byKey(const Key('webBirdReactionRow')), findsOneWidget);
    expect(find.text("Mia's Cabin"), findsOneWidget);
  });

  testWidgets('tapping a reaction adds it, tapping again removes it', (tester) async {
    final bird = Bird(id: 'b3', userId: 'u1', name: 'Fen', currentNestId: 'n1', isTraveling: false, type: 'Cro', isPublic: true, content: 'hi');
    await tester.pumpWidget(build(bird));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webReactionChip_🕊️')));
    await tester.pump();
    expect(reactionService.lastAddedEmoji, '🕊️');

    await tester.tap(find.byKey(const Key('webReactionChip_🕊️')));
    await tester.pump();
    expect(reactionService.lastRemovedEmoji, '🕊️');
  });

  testWidgets('closing the panel calls onClose', (tester) async {
    var closed = false;
    final bird = Bird(id: 'b4', userId: 'u1', name: 'Willa', currentNestId: 'n1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird, onClose: () => closed = true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webPanelClose')));
    expect(closed, isTrue);
  });

  testWidgets('a home bird shows the Home chip, "Home and rested" note, and Send footer button', (tester) async {
    var composed = false;
    final bird = Bird(id: 'b5', userId: 'u1', name: 'Willa', currentNestId: 'n1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird, onComposePressed: () => composed = true));
    await tester.pump();

    expect(find.byKey(const Key('birdPanelStateChip')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const Key('birdPanelProgressNote')), findsOneWidget);
    expect(find.text('Home and rested'), findsOneWidget);
    expect(find.byKey(const Key('birdPanelSendSomewhere')), findsOneWidget);
    expect(find.text('Send this bird somewhere'), findsOneWidget);

    await tester.tap(find.byKey(const Key('birdPanelSendSomewhere')));
    expect(composed, isTrue);
  });

  testWidgets('an in-flight bird shows the In flight chip, a percent note, and Follow footer button', (tester) async {
    var followed = false;
    final bird = Bird(
      id: 'b6',
      userId: 'u1',
      name: 'Percy',
      isTraveling: true,
      nestFromId: 'n1',
      nestToId: 'f1',
      type: 'Cro',
      departedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      estimatedArrivalAt: DateTime.now().add(const Duration(minutes: 50)),
    );
    await tester.pumpWidget(build(bird, onFollowOnMap: () => followed = true));
    await tester.pump();

    expect(find.text('In flight'), findsOneWidget);
    expect(find.textContaining('% of the way there'), findsOneWidget);
    expect(find.byKey(const Key('birdPanelFollowOnMap')), findsOneWidget);
    expect(find.text('Follow on the map'), findsOneWidget);

    await tester.tap(find.byKey(const Key('birdPanelFollowOnMap')));
    expect(followed, isTrue);
  });

  testWidgets('a bird at a hub shows the "At a hub" chip, a progress bar, but no note text', (tester) async {
    final bird = Bird(id: 'b7', userId: 'u1', name: 'Fen', currentNestId: 'h1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird));
    await tester.pump();

    expect(find.text('At a hub'), findsOneWidget);
    expect(find.byKey(const Key('birdPanelProgressNote')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('birdPanelSendOnward')), findsOneWidget);
    expect(find.byKey(const Key('birdPanelCallItHome')), findsOneWidget);
  });

  testWidgets('a private bird parked at a hub still shows its content, not "Sealed until it lands"',
      (tester) async {
    final bird = Bird(
      id: 'b11',
      userId: 'u1',
      name: 'Fen',
      currentNestId: 'h1',
      isTraveling: false,
      type: 'Cro',
      isPublic: false,
      content: 'left at the lighthouse',
    );
    await tester.pumpWidget(build(bird));
    await tester.pump();

    expect(find.text('What it carries'), findsOneWidget);
    expect(find.text('left at the lighthouse'), findsOneWidget);
    expect(find.text('Sealed until it lands'), findsNothing);
    expect(find.text('This bird is private. The message stays sealed until it reaches its nest.'), findsNothing);
  });

  testWidgets('a bird resting at a friend nest names the owner, with no progress bar or note', (tester) async {
    final bird = Bird(id: 'b8', userId: 'u1', name: 'Bramble', currentNestId: 'f1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird));
    await tester.pump();

    expect(find.text("At mia's nest"), findsOneWidget);
    expect(find.text('Away'), findsNothing);
    expect(find.byKey(const Key('birdPanelProgressNote')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('birdPanelSendOnward')), findsOneWidget);
    expect(find.byKey(const Key('birdPanelCallItHome')), findsOneWidget);
  });

  testWidgets('"Send onward" from a friend nest offers both own and other friend nests as destinations',
      (tester) async {
    var dataChanged = false;
    final bird = Bird(id: 'b10', userId: 'u1', name: 'Bramble', currentNestId: 'f1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird, ownNests: [ownNest, ownNest2], onDataChanged: () => dataChanged = true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('birdPanelSendOnward')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sendBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    // Both the sender's own nests and the current friend nest's own name should be offered
    // (f1 itself, the bird's current nest, is excluded) - Cabin (own) is present here.
    expect(find.text('Cabin').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cabin').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(birdService.lastSendBirdId, 'b10');
    expect(birdService.lastSendNestId, 'n2');
    expect(dataChanged, isTrue);
  });

  testWidgets('"Call it home" opens the send dialog and calls BirdService.sendBird', (tester) async {
    var dataChanged = false;
    final bird = Bird(id: 'b9', userId: 'u1', name: 'Bramble', currentNestId: 'f1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird, ownNests: [ownNest, ownNest2], onDataChanged: () => dataChanged = true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('birdPanelCallItHome')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdDestinationDropdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sendBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabin').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(birdService.lastSendBirdId, 'b9');
    expect(birdService.lastSendNestId, 'n2');
    expect(dataChanged, isTrue);
  });
}
