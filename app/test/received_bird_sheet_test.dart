import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/bird.dart';
import 'package:cro_app/models/pinned_bird.dart';
import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/services/bird_service.dart';
import 'package:cro_app/services/pin_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/widgets/received_bird_sheet.dart';

// markBirdRead isn't overridden - it's fire-and-forget and wrapped in a swallowed try/catch
// by ReceivedBirdSheet itself (see its _markRead), so falling through to noSuchMethod's
// throw is harmless here and simpler than faking a full Bird return value.
class _FakeBirdService implements BirdService {
  String? lastShooedBirdId;
  // Set to make shooBird throw instead, to exercise the error-toast path.
  Object? shooError;

  @override
  Future<Bird> shooBird(String token, String birdId) async {
    if (shooError != null) throw shooError!;
    lastShooedBirdId = birdId;
    return Bird(id: birdId, userId: 'sender1', name: 'Otto', isTraveling: true, type: 'Cro');
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<UserProfile> getUser(String userId) async =>
      UserProfile(id: userId, username: 'Sender', email: 's@example.com');

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakePinService implements PinService {
  String? lastPinnedBirdId;
  // Set to simulate opening a message pinned on an earlier visit.
  PinnedBird? existingPin;

  @override
  Future<PinnedBird?> getPinStatus(String token, String birdId) async => existingPin;

  @override
  Future<PinnedBird> pinBird(String token, String birdId) async {
    lastPinnedBirdId = birdId;
    return PinnedBird(
      id: 'pin1',
      receiverId: 'me',
      senderId: 'sender1',
      senderUsername: 'Sender',
      birdId: birdId,
      birdName: 'Otto',
      type: 'Cro',
      content: 'hi',
      isPublic: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool isPublic,
    PinService? pinService,
    BirdService? birdService,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ReceivedBirdSheet.show(
              context,
              birdId: 'b1',
              name: 'Otto',
              type: 'Cro',
              senderId: 'sender1',
              content: 'hi there',
              isRead: true,
              isPublic: isPublic,
              token: 'tok',
              profileService: _FakeProfileService(),
              birdService: birdService ?? _FakeBirdService(),
              pinService: pinService ?? _FakePinService(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('pinning a public delivered bird tells the receiver it is now visible to everyone', (tester) async {
    await pump(tester, isPublic: true);

    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('receivedBirdPinButton')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('Pinned for everyone to see'), findsOneWidget);
  });

  testWidgets('pinning a private delivered bird tells the receiver it is saved just for them', (tester) async {
    await pump(tester, isPublic: false);

    await tester.tap(find.byKey(const Key('receivedBirdPinButton')));
    await tester.pumpAndSettle();

    expect(find.text('Pinned to your saved messages'), findsOneWidget);
  });

  testWidgets('the pin button is disabled once pinned - no unpin option from this sheet', (tester) async {
    final pinService = _FakePinService();
    await pump(tester, isPublic: false, pinService: pinService);

    await tester.tap(find.byKey(const Key('receivedBirdPinButton')));
    await tester.pumpAndSettle();
    expect(pinService.lastPinnedBirdId, 'b1');

    final button = tester.widget<IconButton>(find.byKey(const Key('receivedBirdPinButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('opening a message pinned on an earlier visit shows it as already pinned', (tester) async {
    final pinService = _FakePinService()
      ..existingPin = PinnedBird(
        id: 'pin1',
        receiverId: 'me',
        senderId: 'sender1',
        senderUsername: 'Sender',
        birdId: 'b1',
        birdName: 'Otto',
        type: 'Cro',
        content: 'hi',
        isPublic: false,
        createdAt: DateTime.now(),
      );
    await pump(tester, isPublic: false, pinService: pinService);

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    final button = tester.widget<IconButton>(find.byKey(const Key('receivedBirdPinButton')));
    expect(button.onPressed, isNull);
    expect(pinService.lastPinnedBirdId, isNull);
  });

  testWidgets('shooing a delivered bird sends it home and closes the sheet', (tester) async {
    final birdService = _FakeBirdService();
    await pump(tester, isPublic: false, birdService: birdService);

    await tester.tap(find.byKey(const Key('receivedBirdShooButton')));
    await tester.pumpAndSettle();

    expect(birdService.lastShooedBirdId, 'b1');
    expect(find.byKey(const Key('receivedBirdSheet')), findsNothing);
  });

  testWidgets('a failed shoo shows the error and leaves the sheet open', (tester) async {
    final birdService = _FakeBirdService()..shooError = Exception('This bird has no home nest to return to.');
    await pump(tester, isPublic: false, birdService: birdService);

    await tester.tap(find.byKey(const Key('receivedBirdShooButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('no home nest'), findsOneWidget);
    expect(find.byKey(const Key('receivedBirdSheet')), findsOneWidget);
  });
}
