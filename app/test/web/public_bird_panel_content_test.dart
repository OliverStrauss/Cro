import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/public_bird.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/widgets/public_bird_panel_content.dart';

class _FakeFriendsService implements FriendsService {
  String? lastRequestedUsername;
  Object? errorToThrow;

  @override
  Future<void> sendFriendRequest(String token, String username) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastRequestedUsername = username;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by PublicBirdPanelContent');
}

void main() {
  late _FakeFriendsService friendsService;
  late AuthState authState;

  setUp(() {
    friendsService = _FakeFriendsService();
    authState = AuthState()..login('a.b.c');
  });

  final bird = PublicBird(
    id: 'pb1',
    senderUserId: 'u2',
    senderUsername: 'stranger_sam',
    type: 'Cro',
    content: 'Hello from afar',
    latitude: 45.0,
    longitude: -90.0,
  );

  Widget build({VoidCallback? onClose}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: PublicBirdPanelContent(
          bird: bird,
          authState: authState,
          friendsService: friendsService,
          onClose: onClose ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows the sender identity and the bird content, with no nest/ETA row', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.text('stranger_sam'), findsOneWidget);
    expect(find.text('Hello from afar'), findsOneWidget);
    expect(find.text('Flying to'), findsNothing);
    expect(find.text('Arrival'), findsNothing);
  });

  testWidgets('tapping Add Friend sends a request for the sender\'s username', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();

    await tester.tap(find.byKey(const Key('publicBirdPanelAddFriend')));
    await tester.pump();

    expect(friendsService.lastRequestedUsername, 'stranger_sam');
    expect(find.text('Request sent'), findsOneWidget);
  });

  testWidgets('a failed request shows an error and leaves the button re-tappable', (tester) async {
    friendsService.errorToThrow = Exception('A relationship with this user already exists.');
    await tester.pumpWidget(build());
    await tester.pump();

    await tester.tap(find.byKey(const Key('publicBirdPanelAddFriend')));
    await tester.pumpAndSettle();

    expect(friendsService.lastRequestedUsername, isNull);
    expect(find.text('Add stranger_sam as a friend'), findsOneWidget);
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('closing the panel calls onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(build(onClose: () => closed = true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webPanelClose')));
    expect(closed, isTrue);
  });
}
