import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/models/event.dart';
import 'package:cro_app/web/screens/web_you_screen.dart';

class _FakeProfileService implements ProfileService {
  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebYouScreen');
}

AppEvent _event(String id, String kind) => AppEvent(
  id: id,
  kind: kind,
  displayText: '',
  isNotification: false,
  isRead: true,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late AuthState authState;

  setUp(() {
    authState = AuthState()..login('a.b.c');
  });

  Widget build({
    bool isAdmin = false,
    int birdCount = 0,
    int nestCount = 0,
    int friendCount = 0,
    List<AppEvent> events = const [],
    VoidCallback? onNavigateFriends,
    VoidCallback? onNavigateHubs,
  }) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebYouScreen(
          authState: authState,
          profileService: _FakeProfileService(),
          username: 'oliver_s',
          profilePictureUrl: null,
          isAdmin: isAdmin,
          birdCount: birdCount,
          nestCount: nestCount,
          friendCount: friendCount,
          events: events,
          onDataChanged: () {},
          onNavigateFriends: onNavigateFriends ?? () {},
          onNavigateHubs: onNavigateHubs ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows the username and stat tiles', (tester) async {
    await tester.pumpWidget(build(birdCount: 3, nestCount: 2, friendCount: 5));
    expect(find.text('oliver_s'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('flights logged counts only BirdDeparted events', (tester) async {
    await tester.pumpWidget(build(events: [
      _event('e1', EventKind.birdDeparted),
      _event('e2', EventKind.birdDeparted),
      _event('e3', EventKind.birdArrived),
    ]));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows an Admin badge only for admins', (tester) async {
    await tester.pumpWidget(build());
    expect(find.text('Admin'), findsNothing);

    await tester.pumpWidget(build(isAdmin: true));
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('settings rows navigate to Friends/Hubs and sign out', (tester) async {
    var wentToFriends = false;
    var wentToHubs = false;
    await tester.pumpWidget(build(onNavigateFriends: () => wentToFriends = true, onNavigateHubs: () => wentToHubs = true));

    await tester.tap(find.byKey(const Key('webSettingsBlockedUsers')));
    expect(wentToFriends, isTrue);

    await tester.tap(find.byKey(const Key('webSettingsHubSuggestions')));
    expect(wentToHubs, isTrue);

    expect(authState.isLoggedIn, isTrue);
    await tester.tap(find.byKey(const Key('webSettingsSignOut')));
    expect(authState.isLoggedIn, isFalse);
  });
}
