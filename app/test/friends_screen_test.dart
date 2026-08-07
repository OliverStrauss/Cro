import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/friends_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/utils/color_utils.dart';

class _FakeFriendsService implements FriendsService {
  List<Friend> friendsToReturn = [];
  List<FriendRequest> incomingToReturn = [];
  List<FriendRequest> outgoingToReturn = [];
  Object? loadErrorToThrow;
  Object? sendErrorToThrow;

  String? lastSentUsername;
  String? lastAcceptedRequesterId;
  String? lastRemovedUserId;
  String? lastColoredFriendId;
  String? lastSetColor;

  @override
  Future<List<Friend>> getFriends(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return friendsToReturn;
  }

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return incomingToReturn;
  }

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return outgoingToReturn;
  }

  @override
  Future<void> sendFriendRequest(String token, String username) async {
    lastSentUsername = username;
    if (sendErrorToThrow != null) throw sendErrorToThrow!;
  }

  @override
  Future<void> acceptFriendRequest(String token, String requesterId) async {
    lastAcceptedRequesterId = requesterId;
    incomingToReturn = incomingToReturn.where((r) => r.userId != requesterId).toList();
  }

  @override
  Future<void> removeFriend(String token, String userId) async {
    lastRemovedUserId = userId;
    friendsToReturn = friendsToReturn.where((f) => f.userId != userId).toList();
    incomingToReturn = incomingToReturn.where((r) => r.userId != userId).toList();
    outgoingToReturn = outgoingToReturn.where((r) => r.userId != userId).toList();
  }

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => [];

  @override
  Future<void> setFriendColor(String token, String friendId, String color) async {
    lastColoredFriendId = friendId;
    lastSetColor = color;
    friendsToReturn = friendsToReturn
        .map((f) => f.userId == friendId ? Friend(userId: f.userId, username: f.username, color: color) : f)
        .toList();
  }
}

void main() {
  testWidgets('shows loading indicator before data loads', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));

    expect(find.byKey(const Key('friendsLoadingIndicator')), findsOneWidget);
  });

  testWidgets('renders the friends list once loaded', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..friendsToReturn = [Friend(userId: 'u1', username: 'alice', color: '#E53935')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.byKey(const Key('noFriendsMessage')), findsNothing);
  });

  testWidgets('shows initials when a friend has no profile picture set', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..friendsToReturn = [Friend(userId: 'u1', username: 'alice', color: '#E53935')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    final aliceAvatar = tester.widget<CircleAvatar>(find.byKey(const Key('friendAvatar_u1')));
    expect(aliceAvatar.backgroundImage, isNull);
    expect(find.descendant(of: find.byKey(const Key('friendAvatar_u1')), matching: find.text('A')),
        findsOneWidget);
  });

  testWidgets('falls back to initials when a friend\'s profile picture fails to load',
      (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..friendsToReturn = [
        Friend(
            userId: 'u2',
            username: 'bob',
            color: '#1E88E5',
            profilePictureUrl: 'https://example.com/bob.png'),
      ];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();
    // Every network image fetch in this test harness returns a stubbed 400, so bob's
    // picture is expected to fail here - this is exercising the fallback path itself,
    // not a real successful load (which flutter test cannot produce for NetworkImage).

    final bobAvatar = tester.widget<CircleAvatar>(find.byKey(const Key('friendAvatar_u2')));
    expect(bobAvatar.backgroundImage, isNull);
    expect(find.descendant(of: find.byKey(const Key('friendAvatar_u2')), matching: find.text('B')),
        findsOneWidget);
  });

  testWidgets('shows a message when the friends list is empty', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noFriendsMessage')), findsOneWidget);
  });

  testWidgets('incoming requests section only shows when there are requests', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');

    final noRequestsService = _FakeFriendsService();
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(
          key: const Key('withoutRequests'), authState: authState, friendsService: noRequestsService),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('incomingRequestsSection')), findsNothing);

    final withRequestsService = _FakeFriendsService()
      ..incomingToReturn = [FriendRequest(userId: 'u2', username: 'bob')];
    // Distinct key from the widget above - without one, Flutter would treat this as an
    // update to the same element (same type, same tree position) and reuse the old State
    // via didUpdateWidget instead of remounting with the new fake service via initState.
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(
          key: const Key('withRequests'), authState: authState, friendsService: withRequestsService),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('incomingRequestsSection')), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('pending requests section only shows when there are outgoing requests',
      (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');

    final noRequestsService = _FakeFriendsService();
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(
          key: const Key('withoutPending'), authState: authState, friendsService: noRequestsService),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outgoingRequestsSection')), findsNothing);

    final withPendingService = _FakeFriendsService()
      ..outgoingToReturn = [FriendRequest(userId: 'u3', username: 'dave')];
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(
          key: const Key('withPending'), authState: authState, friendsService: withPendingService),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outgoingRequestsSection')), findsOneWidget);
    expect(find.text('dave'), findsOneWidget);
  });

  testWidgets('canceling a pending request calls removeFriend and refreshes', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..outgoingToReturn = [FriendRequest(userId: 'u3', username: 'dave')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancelRequestButton_u3')));
    await tester.pumpAndSettle();

    expect(fakeService.lastRemovedUserId, 'u3');
    expect(find.byKey(const Key('outgoingRequestsSection')), findsNothing);
  });

  testWidgets('sending a friend request succeeds, clears the field, and shows a success toast',
      (WidgetTester tester) async {
    final fakeService = _FakeFriendsService();
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addFriendUsernameField')), 'carol');
    await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastSentUsername, 'carol');
    expect(find.text('Friend request sent to carol'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byKey(const Key('addFriendUsernameField')));
    expect(textField.controller!.text, isEmpty);
  });

  testWidgets('shows an error toast when sending a friend request fails', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..sendErrorToThrow = FriendsException('No user with that username.');
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addFriendUsernameField')), 'nobody');
    await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
    await tester.pumpAndSettle();

    expect(find.text('No user with that username.'), findsOneWidget);
  });

  testWidgets('accepting a request removes it from incoming and refreshes friends', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..incomingToReturn = [FriendRequest(userId: 'u2', username: 'bob')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('acceptRequestButton_u2')));
    await tester.pumpAndSettle();

    expect(fakeService.lastAcceptedRequesterId, 'u2');
    expect(find.byKey(const Key('incomingRequestsSection')), findsNothing);
  });

  testWidgets('removing a friend calls the service and refreshes the list', (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..friendsToReturn = [Friend(userId: 'u1', username: 'alice', color: '#E53935')];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('removeFriendButton_u1')));
    await tester.pumpAndSettle();

    expect(fakeService.lastRemovedUserId, 'u1');
    expect(find.byKey(const Key('noFriendsMessage')), findsOneWidget);
  });

  testWidgets('picking a color for a friend calls the service and refreshes the list',
      (WidgetTester tester) async {
    final fakeService = _FakeFriendsService()
      ..friendsToReturn = [Friend(userId: 'u1', username: 'alice', color: friendColorPalette[0])];
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(authState: authState, friendsService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friendTile_u1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('colorOption_${friendColorPalette[1]}')));
    await tester.pumpAndSettle();

    expect(fakeService.lastColoredFriendId, 'u1');
    expect(fakeService.lastSetColor, friendColorPalette[1]);
  });
}
