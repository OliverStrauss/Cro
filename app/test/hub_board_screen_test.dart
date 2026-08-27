import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/hub_message.dart';
import 'package:cro_app/screens/hub_board_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/state/auth_state.dart';

class _FakeHubService implements HubService {
  List<HubMessage> messagesToReturn = [];
  Object? loadErrorToThrow;

  @override
  Future<List<HubMessage>> listMessages(String token, String hubId) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return messagesToReturn;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeFriendsService implements FriendsService {
  List<Friend> friendsToReturn = [];
  List<FriendRequest> incomingToReturn = [];
  List<FriendRequest> outgoingToReturn = [];
  String? lastFriendRequestUsername;
  Object? sendRequestErrorToThrow;

  @override
  Future<List<Friend>> getFriends(String token) async => friendsToReturn;

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => incomingToReturn;

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async => outgoingToReturn;

  @override
  Future<void> sendFriendRequest(String token, String username) async {
    if (sendRequestErrorToThrow != null) throw sendRequestErrorToThrow!;
    lastFriendRequestUsername = username;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

// A syntactically valid (unsigned) JWT with the given subject - HubBoardScreen decodes
// this client-side to exclude the viewer's own messages from "Add Friend".
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({'alg': 'HS256'})}.${segment({'sub': userId})}.sig';
}

HubMessage _messageFrom(String senderId, String senderUsername, {String content = 'hello'}) => HubMessage(
      id: 'msg-$senderId-${DateTime.now().microsecondsSinceEpoch}',
      senderId: senderId,
      senderUsername: senderUsername,
      birdName: 'Test Bird',
      originNestName: 'Origin Nest',
      type: 'Cro',
      content: content,
      createdAt: DateTime.now(),
    );

void main() {
  testWidgets('shows loading indicator before data loads', (WidgetTester tester) async {
    final hubService = _FakeHubService();
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: _FakeFriendsService(),
      ),
    ));

    expect(find.byKey(const Key('hubBoardLoadingIndicator')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state with retry on load failure', (WidgetTester tester) async {
    final hubService = _FakeHubService()..loadErrorToThrow = Exception('boom');
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: _FakeFriendsService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hubBoardErrorState')), findsOneWidget);
  });

  testWidgets('shows empty state when the hub has no messages', (WidgetTester tester) async {
    final hubService = _FakeHubService();
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: _FakeFriendsService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hubBoardEmptyState')), findsOneWidget);
  });

  testWidgets('renders a card with sender, bird name, origin, and content', (WidgetTester tester) async {
    final message = _messageFrom('stranger-1', 'Stranger', content: 'hi there');
    final hubService = _FakeHubService()..messagesToReturn = [message];
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: _FakeFriendsService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('hubMessageCard_${message.id}')), findsOneWidget);
    expect(find.text('Stranger'), findsOneWidget);
    expect(find.textContaining('Test Bird'), findsOneWidget);
    expect(find.textContaining('Origin Nest'), findsOneWidget);
    expect(find.text('hi there'), findsOneWidget);
  });

  testWidgets('hides Add Friend for a message the viewer sent themself', (WidgetTester tester) async {
    final message = _messageFrom('viewer', 'Me');
    final hubService = _FakeHubService()..messagesToReturn = [message];
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: _FakeFriendsService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('hubMessageAddFriendButton_${message.id}')), findsNothing);
  });

  testWidgets('hides Add Friend for an already-accepted friend', (WidgetTester tester) async {
    final message = _messageFrom('friend-1', 'Friendo');
    final hubService = _FakeHubService()..messagesToReturn = [message];
    final friendsService = _FakeFriendsService()
      ..friendsToReturn = [Friend(userId: 'friend-1', username: 'Friendo')];
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: friendsService,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('hubMessageAddFriendButton_${message.id}')), findsNothing);
  });

  testWidgets('hides Add Friend when a request is already pending either direction', (WidgetTester tester) async {
    final message = _messageFrom('pending-1', 'Pending');
    final hubService = _FakeHubService()..messagesToReturn = [message];
    final friendsService = _FakeFriendsService()
      ..outgoingToReturn = [FriendRequest(userId: 'pending-1', username: 'Pending')];
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: friendsService,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('hubMessageAddFriendButton_${message.id}')), findsNothing);
  });

  testWidgets('tapping Add Friend for an unrelated sender sends a friend request', (WidgetTester tester) async {
    final message = _messageFrom('stranger-1', 'Stranger');
    final hubService = _FakeHubService()..messagesToReturn = [message];
    final friendsService = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('viewer'));

    await tester.pumpWidget(MaterialApp(
      home: HubBoardScreen(
        authState: authState,
        hubId: 'hub-1',
        hubName: 'Test Hub',
        hubService: hubService,
        friendsService: friendsService,
      ),
    ));
    await tester.pumpAndSettle();

    final addFriendButton = find.byKey(Key('hubMessageAddFriendButton_${message.id}'));
    expect(addFriendButton, findsOneWidget);

    await tester.tap(addFriendButton);
    await tester.pumpAndSettle();

    expect(friendsService.lastFriendRequestUsername, 'Stranger');
  });
}
