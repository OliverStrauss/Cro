import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/bird_reaction.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/bird_reaction_service.dart';
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

void main() {
  final ownNest = Waypoint(id: 'n1', userId: 'u1', name: 'Home Roost', latitude: 42, longitude: -93);
  final friendNest = Waypoint(id: 'f1', userId: 'u2', name: "Mia's Cabin", latitude: 43, longitude: -92, username: 'mia');
  final hub = Hub(id: 'h1', name: 'Lighthouse', latitude: 44, longitude: -91, status: 'Approved', createdByUserId: 'admin');

  late _FakeBirdReactionService reactionService;
  late AuthState authState;

  setUp(() {
    reactionService = _FakeBirdReactionService();
    authState = AuthState()..login('a.b.c');
  });

  Widget build(Bird bird, {VoidCallback? onClose}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: BirdPanelContent(
          bird: bird,
          ownNests: [ownNest],
          friendWaypoints: [friendNest],
          hubs: [hub],
          authState: authState,
          reactionService: reactionService,
          onClose: onClose ?? () {},
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

    await tester.tap(find.byKey(const Key('webReactionChip_👍')));
    await tester.pump();
    expect(reactionService.lastAddedEmoji, '👍');

    await tester.tap(find.byKey(const Key('webReactionChip_👍')));
    await tester.pump();
    expect(reactionService.lastRemovedEmoji, '👍');
  });

  testWidgets('closing the panel calls onClose', (tester) async {
    var closed = false;
    final bird = Bird(id: 'b4', userId: 'u1', name: 'Willa', currentNestId: 'n1', isTraveling: false, type: 'Cro');
    await tester.pumpWidget(build(bird, onClose: () => closed = true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webPanelClose')));
    expect(closed, isTrue);
  });
}
