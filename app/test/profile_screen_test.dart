import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_bird.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/models/user_search_result.dart';
import 'package:cro_app/models/waypoint.dart';
import 'package:cro_app/screens/profile_screen.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/utils/color_utils.dart';

class _FakeProfileService implements ProfileService {
  UserProfile? profileToReturn;
  Object? loadErrorToThrow;
  XFile? imageToReturn;
  Object? uploadErrorToThrow;

  String? lastUploadedFilename;
  String? lastUploadedContentType;

  @override
  Future<UserProfile> getUser(String userId) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return profileToReturn!;
  }

  @override
  Future<XFile?> pickImage() async => imageToReturn;

  @override
  Future<String> uploadProfilePicture(
    String token,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    if (uploadErrorToThrow != null) throw uploadErrorToThrow!;
    lastUploadedFilename = filename;
    lastUploadedContentType = contentType;
    return 'https://example.com/pictures/new.png';
  }
}

class _FakeFriendsService implements FriendsService {
  List<Friend> friendsToReturn = [];
  List<FriendRequest> incomingToReturn = [];
  List<FriendRequest> outgoingToReturn = [];
  List<UserSearchResult> searchResultsToReturn = [];
  Object? loadErrorToThrow;
  Object? sendErrorToThrow;
  Object? searchErrorToThrow;

  String? lastSentUsername;
  String? lastAcceptedRequesterId;
  String? lastRemovedUserId;
  String? lastColoredFriendId;
  String? lastSetColor;
  String? lastSearchQuery;

  @override
  Future<List<UserSearchResult>> searchUsers(String token, String query) async {
    lastSearchQuery = query;
    if (searchErrorToThrow != null) throw searchErrorToThrow!;
    return searchResultsToReturn;
  }

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
    incomingToReturn = incomingToReturn
        .where((r) => r.userId != requesterId)
        .toList();
  }

  @override
  Future<void> removeFriend(String token, String userId) async {
    lastRemovedUserId = userId;
    friendsToReturn = friendsToReturn.where((f) => f.userId != userId).toList();
    incomingToReturn = incomingToReturn
        .where((r) => r.userId != userId)
        .toList();
    outgoingToReturn = outgoingToReturn
        .where((r) => r.userId != userId)
        .toList();
  }

  @override
  Future<List<Waypoint>> getFriendsWaypoints(String token) async => [];

  @override
  Future<List<FriendBird>> getFriendsBirds(String token) async => [];

  @override
  Future<void> setFriendColor(
    String token,
    String friendId,
    String color,
  ) async {
    lastColoredFriendId = friendId;
    lastSetColor = color;
    friendsToReturn = friendsToReturn
        .map(
          (f) => f.userId == friendId
              ? Friend(userId: f.userId, username: f.username, color: color)
              : f,
        )
        .toList();
  }
}

// A syntactically valid (unsigned) JWT with the given subject - ProfileScreen decodes
// this client-side to know which user id to fetch.
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({'alg': 'HS256'})}.${segment({'sub': userId})}.sig';
}

void main() {
  testWidgets('shows loading indicator before data loads', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService();
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );

    expect(find.byKey(const Key('profileLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows the username once loaded', (WidgetTester tester) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'u1',
        username: 'alice',
        email: 'alice@example.com',
      );
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('falls back to initials when the profile picture fails to load', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'u1',
        username: 'alice',
        email: 'alice@example.com',
        profilePictureUrl: 'https://example.com/pic.png',
      );
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Every network image fetch in this test harness returns a stubbed 400, so the
    // picture is expected to fail here - this exercises the fallback path itself, not a
    // real successful load (which flutter test cannot produce for NetworkImage).

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('shows an error and retry button on failure', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..loadErrorToThrow = ProfileException('Could not load profile');
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Sign Out is tappable even when the profile fails to load', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..loadErrorToThrow = ProfileException('Could not load profile');
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logoutButton')));

    expect(authState.isLoggedIn, isFalse);
  });

  testWidgets('picking and uploading a picture refetches the profile', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'u1',
        username: 'alice',
        email: 'alice@example.com',
      )
      ..imageToReturn = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        path: 'avatar.png',
        mimeType: 'image/png',
      );
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(fakeProfile.lastUploadedFilename, 'avatar.png');
    expect(fakeProfile.lastUploadedContentType, 'image/png');
    expect(find.text('Profile picture updated'), findsOneWidget);
  });

  testWidgets('canceling the image picker does not attempt an upload', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'u1',
        username: 'alice',
        email: 'alice@example.com',
      )
      ..imageToReturn = null;
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(fakeProfile.lastUploadedFilename, isNull);
  });

  testWidgets('shows an error toast when the upload fails', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'u1',
        username: 'alice',
        email: 'alice@example.com',
      )
      ..imageToReturn = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        path: 'avatar.png',
        mimeType: 'image/png',
      )
      ..uploadErrorToThrow = ProfileException(
        'Could not upload profile picture',
      );
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(find.text('Could not upload profile picture'), findsOneWidget);
  });

  testWidgets('renders the friends row once loaded', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..friendsToReturn = [
        Friend(userId: 'u1', username: 'alice', color: '#E53935'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.byKey(const Key('noFriendsMessage')), findsNothing);
  });

  testWidgets('shows initials on a friend card with no profile picture', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..friendsToReturn = [
        Friend(userId: 'u1', username: 'alice', color: '#E53935'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aliceAvatar = tester.widget<CircleAvatar>(
      find.byKey(const Key('friendAvatar_u1')),
    );
    expect(aliceAvatar.backgroundImage, isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('friendAvatar_u1')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a message when the friends list is empty', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService();
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noFriendsMessage')), findsOneWidget);
  });

  testWidgets('invites section only shows when there are incoming requests', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final authState = AuthState()..login(_fakeJwtFor('me'));

    final noRequestsService = _FakeFriendsService();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          key: const Key('withoutRequests'),
          authState: authState,
          profileService: fakeProfile,
          friendsService: noRequestsService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('incomingRequestsSection')), findsNothing);

    final withRequestsService = _FakeFriendsService()
      ..incomingToReturn = [FriendRequest(userId: 'u2', username: 'bob')];
    // Distinct key from the widget above - without one, Flutter would treat this as an
    // update to the same element (same type, same tree position) and reuse the old State
    // via didUpdateWidget instead of remounting with the new fake service via initState.
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          key: const Key('withRequests'),
          authState: authState,
          profileService: fakeProfile,
          friendsService: withRequestsService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('incomingRequestsSection')), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets(
    'pending requests section only shows when there are outgoing requests',
    (WidgetTester tester) async {
      final fakeProfile = _FakeProfileService()
        ..profileToReturn = UserProfile(
          id: 'me',
          username: 'me',
          email: 'me@example.com',
        );
      final authState = AuthState()..login(_fakeJwtFor('me'));

      final noRequestsService = _FakeFriendsService();
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            key: const Key('withoutPending'),
            authState: authState,
            profileService: fakeProfile,
            friendsService: noRequestsService,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outgoingRequestsSection')), findsNothing);

      final withPendingService = _FakeFriendsService()
        ..outgoingToReturn = [FriendRequest(userId: 'u3', username: 'dave')];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            key: const Key('withPending'),
            authState: authState,
            profileService: fakeProfile,
            friendsService: withPendingService,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outgoingRequestsSection')), findsOneWidget);
      expect(find.text('dave'), findsOneWidget);
    },
  );

  testWidgets('canceling a pending request calls removeFriend and refreshes', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..outgoingToReturn = [FriendRequest(userId: 'u3', username: 'dave')];
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancelRequestButton_u3')));
    await tester.pumpAndSettle();

    expect(fakeFriends.lastRemovedUserId, 'u3');
    expect(find.byKey(const Key('outgoingRequestsSection')), findsNothing);
  });

  testWidgets(
    'sending a friend request succeeds, clears the field, and shows a success toast',
    (WidgetTester tester) async {
      final fakeProfile = _FakeProfileService()
        ..profileToReturn = UserProfile(
          id: 'me',
          username: 'me',
          email: 'me@example.com',
        );
      final fakeFriends = _FakeFriendsService();
      final authState = AuthState()..login(_fakeJwtFor('me'));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authState: authState,
            profileService: fakeProfile,
            friendsService: fakeFriends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('addFriendUsernameField')),
        'carol',
      );
      await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
      await tester.pumpAndSettle();

      expect(fakeFriends.lastSentUsername, 'carol');
      expect(find.text('Friend request sent to carol'), findsOneWidget);
      final textField = tester.widget<TextField>(
        find.byKey(const Key('addFriendUsernameField')),
      );
      expect(textField.controller!.text, isEmpty);
    },
  );

  testWidgets('shows an error toast when sending a friend request fails', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..sendErrorToThrow = FriendsException('No user with that username.');
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('addFriendUsernameField')),
      'nobody',
    );
    await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
    await tester.pumpAndSettle();

    expect(find.text('No user with that username.'), findsOneWidget);
  });

  testWidgets(
    'typing a username shows live suggestions after a short delay, excluding existing friends',
    (WidgetTester tester) async {
      final fakeProfile = _FakeProfileService()
        ..profileToReturn = UserProfile(
          id: 'me',
          username: 'me',
          email: 'me@example.com',
        );
      final fakeFriends = _FakeFriendsService()
        ..friendsToReturn = [
          Friend(userId: 'u1', username: 'alice', color: '#E53935'),
        ]
        ..searchResultsToReturn = [
          UserSearchResult(userId: 'u2', username: 'alicia'),
          // Already a friend - the dropdown must filter this back out even though the
          // (fake) server returned it.
          UserSearchResult(userId: 'u1', username: 'alice'),
        ];
      final authState = AuthState()..login(_fakeJwtFor('me'));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authState: authState,
            profileService: fakeProfile,
            friendsService: fakeFriends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('addFriendUsernameField')),
        'ali',
      );
      // Debounced - nothing shows immediately on keystroke.
      await tester.pump();
      expect(find.byKey(const Key('friendSuggestionsList')), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(fakeFriends.lastSearchQuery, 'ali');
      expect(find.byKey(const Key('friendSuggestionsList')), findsOneWidget);
      expect(find.text('alicia'), findsOneWidget);
      expect(find.byKey(const Key('friendSuggestion_u1')), findsNothing);
    },
  );

  testWidgets(
    'tapping a suggestion sends a friend request immediately and clears the field',
    (WidgetTester tester) async {
      final fakeProfile = _FakeProfileService()
        ..profileToReturn = UserProfile(
          id: 'me',
          username: 'me',
          email: 'me@example.com',
        );
      final fakeFriends = _FakeFriendsService()
        ..searchResultsToReturn = [
          UserSearchResult(userId: 'u2', username: 'alicia'),
        ];
      final authState = AuthState()..login(_fakeJwtFor('me'));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authState: authState,
            profileService: fakeProfile,
            friendsService: fakeFriends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('addFriendUsernameField')),
        'ali',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.byKey(const Key('friendSuggestion_u2')));
      await tester.pumpAndSettle();

      expect(fakeFriends.lastSentUsername, 'alicia');
      expect(find.text('Friend request sent to alicia'), findsOneWidget);
      expect(find.byKey(const Key('friendSuggestionsList')), findsNothing);
      final textField = tester.widget<TextField>(
        find.byKey(const Key('addFriendUsernameField')),
      );
      expect(textField.controller!.text, isEmpty);
    },
  );

  testWidgets('accepting a request removes it from incoming and refreshes friends', (
    WidgetTester tester,
  ) async {
    // The default test surface isn't tall enough to fit the whole combined screen (avatar +
    // friends row + search + invites row) without scrolling, and the invites row is itself a
    // second, nested scrollable that tester.ensureVisible won't reach through - simplest fix
    // is a taller surface so everything renders without needing to scroll.
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..incomingToReturn = [FriendRequest(userId: 'u2', username: 'bob')];
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('acceptRequestButton_u2')));
    await tester.pumpAndSettle();

    expect(fakeFriends.lastAcceptedRequesterId, 'u2');
    expect(find.byKey(const Key('incomingRequestsSection')), findsNothing);
  });

  testWidgets('removing a friend calls the service and refreshes the list', (
    WidgetTester tester,
  ) async {
    final fakeProfile = _FakeProfileService()
      ..profileToReturn = UserProfile(
        id: 'me',
        username: 'me',
        email: 'me@example.com',
      );
    final fakeFriends = _FakeFriendsService()
      ..friendsToReturn = [
        Friend(userId: 'u1', username: 'alice', color: '#E53935'),
      ];
    final authState = AuthState()..login(_fakeJwtFor('me'));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authState: authState,
          profileService: fakeProfile,
          friendsService: fakeFriends,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('removeFriendButton_u1')));
    await tester.pumpAndSettle();

    expect(fakeFriends.lastRemovedUserId, 'u1');
    expect(find.byKey(const Key('noFriendsMessage')), findsOneWidget);
  });

  testWidgets(
    'picking a color for a friend calls the service and refreshes the list',
    (WidgetTester tester) async {
      final fakeProfile = _FakeProfileService()
        ..profileToReturn = UserProfile(
          id: 'me',
          username: 'me',
          email: 'me@example.com',
        );
      final fakeFriends = _FakeFriendsService()
        ..friendsToReturn = [
          Friend(userId: 'u1', username: 'alice', color: friendColorPalette[0]),
        ];
      final authState = AuthState()..login(_fakeJwtFor('me'));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authState: authState,
            profileService: fakeProfile,
            friendsService: fakeFriends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('friendTile_u1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('colorOption_${friendColorPalette[1]}')));
      await tester.pumpAndSettle();

      expect(fakeFriends.lastColoredFriendId, 'u1');
      expect(fakeFriends.lastSetColor, friendColorPalette[1]);
    },
  );
}
