import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/blocked_user.dart';
import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/user_search_result.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_friends_screen.dart';

class _FakeFriendsService implements FriendsService {
  List<Friend> friends = [];
  List<FriendRequest> incoming = [];
  List<FriendRequest> outgoing = [];
  List<BlockedUser> blocked = [];
  List<UserSearchResult> searchResults = [];
  String? lastAcceptedId;
  String? lastSentRequestUsername;

  @override
  Future<List<Friend>> getFriends(String token) async => friends;

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => incoming;

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async => outgoing;

  @override
  Future<List<BlockedUser>> getBlockedUsers(String token) async => blocked;

  @override
  Future<List<UserSearchResult>> searchUsers(String token, String query) async => searchResults;

  @override
  Future<void> sendFriendRequest(String token, String username) async {
    lastSentRequestUsername = username;
  }

  @override
  Future<void> acceptFriendRequest(String token, String requesterId) async {
    lastAcceptedId = requesterId;
  }

  @override
  Future<void> declineFriendRequest(String token, String requesterId) async {}

  @override
  Future<void> removeFriend(String token, String userId) async {}

  @override
  Future<void> blockUser(String token, String userId) async {}

  @override
  Future<void> unblockUser(String token, String userId) async {}

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebFriendsScreen');
}

void main() {
  late _FakeFriendsService friendsService;
  late AuthState authState;

  setUp(() {
    friendsService = _FakeFriendsService();
    authState = AuthState()..login('a.b.c');
  });

  Widget build({List<Waypoint> friendWaypoints = const [], VoidCallback? onDataChanged}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebFriendsScreen(
          authState: authState,
          friendsService: friendsService,
          friendWaypoints: friendWaypoints,
          onDataChanged: onDataChanged ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows an empty state when there are no friends', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.byKey(const Key('noFriendsMessage')), findsOneWidget);
  });

  testWidgets('shows a card per friend, with their nest count', (tester) async {
    friendsService.friends = [Friend(userId: 'u2', username: 'mia', color: '#E53935')];
    await tester.pumpWidget(build(friendWaypoints: [
      Waypoint(id: 'f1', userId: 'u2', name: "Mia's Cabin", latitude: 1, longitude: 1, username: 'mia'),
    ]));
    await tester.pump();

    expect(find.byKey(const Key('webFriendCard_u2')), findsOneWidget);
    expect(find.text('1 nest on your map'), findsOneWidget);
  });

  testWidgets('shows incoming invites and accepting one calls the service', (tester) async {
    friendsService.incoming = [FriendRequest(userId: 'u3', username: 'theo')];
    var changed = false;
    await tester.pumpWidget(build(onDataChanged: () => changed = true));
    await tester.pump();

    expect(find.byKey(const Key('webInviteCard_u3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('webAcceptInviteButton_u3')));
    await tester.pump();

    expect(friendsService.lastAcceptedId, 'u3');
    expect(changed, isTrue);
  });

  testWidgets('typing in search excludes people already in a relationship', (tester) async {
    friendsService.friends = [Friend(userId: 'u2', username: 'mia')];
    friendsService.searchResults = [
      UserSearchResult(userId: 'u2', username: 'mia'),
      UserSearchResult(userId: 'u5', username: 'newperson'),
    ];
    await tester.pumpWidget(build());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('webFriendSearchField')), 'm');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('webFriendSuggestion_u2')), findsNothing);
    expect(find.byKey(const Key('webFriendSuggestion_u5')), findsOneWidget);
  });

  testWidgets('shows outgoing requests and blocked users', (tester) async {
    friendsService.outgoing = [FriendRequest(userId: 'u6', username: 'waiting_on')];
    friendsService.blocked = [BlockedUser(userId: 'u7', username: 'spammer')];
    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.byKey(const Key('webOutgoingRow_u6')), findsOneWidget);
    expect(find.byKey(const Key('webBlockedRow_u7')), findsOneWidget);
  });
}
