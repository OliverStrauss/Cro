import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  String? lastUnpinnedId;

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
  Future<void> unpinBird(String token, String pinId) async {
    lastUnpinnedId = pinId;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  Future<void> pump(WidgetTester tester, {required bool isPublic, PinService? pinService}) async {
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
              birdService: _FakeBirdService(),
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

  testWidgets('tapping the pin icon again unpins it', (tester) async {
    final pinService = _FakePinService();
    await pump(tester, isPublic: false, pinService: pinService);

    await tester.tap(find.byKey(const Key('receivedBirdPinButton')));
    await tester.pumpAndSettle();
    expect(pinService.lastPinnedBirdId, 'b1');
    // Lets the first SnackBar's own timer finish so the second one (queued behind it by
    // ScaffoldMessenger) actually shows within this pumpAndSettle instead of staying queued.
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.byKey(const Key('receivedBirdPinButton')));
    await tester.pumpAndSettle();

    expect(pinService.lastUnpinnedId, 'pin1');
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.text('Unpinned'), findsOneWidget);
  });
}
