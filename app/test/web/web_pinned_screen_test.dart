import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/blocked_user.dart';
import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/pinned_bird.dart';
import 'package:cro_app/models/user_search_result.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/pin_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_pinned_screen.dart';

class _FakePinService implements PinService {
  List<PinnedBird> mineToReturn = [];
  List<PinnedBird> publicToReturn = [];

  @override
  Future<List<PinnedBird>> listMyPins(String token) async => mineToReturn;

  @override
  Future<List<PinnedBird>> listPublicPins(String token) async => publicToReturn;

  @override
  Future<void> unpinBird(String token, String pinId) async {
    mineToReturn = mineToReturn.where((p) => p.id != pinId).toList();
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebPinnedScreen');
}

class _FakeFriendsService implements FriendsService {
  @override
  Future<List<Friend>> getFriends(String token) async => [];

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => [];

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async => [];

  @override
  Future<List<BlockedUser>> getBlockedUsers(String token) async => [];

  @override
  Future<List<UserSearchResult>> searchUsers(String token, String query) async => [];

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebPinnedScreen');
}

// A syntactically valid (unsigned) JWT with the given subject - WebPinnedScreen decodes this
// client-side to know the viewer's own id (same helper as web_shell_screen_test.dart).
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({'alg': 'HS256'})}.${segment({'sub': userId})}.sig';
}

PinnedBird _pin(String id, {String? imageUrl}) => PinnedBird(
  id: id,
  receiverId: 'u1',
  senderId: 'u2',
  senderUsername: 'wren',
  birdId: 'b1',
  birdName: 'Robin',
  originNestName: 'Ames',
  type: 'text',
  imageUrl: imageUrl,
  isPublic: false,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late _FakePinService pinService;
  late _FakeFriendsService friendsService;
  late AuthState authState;

  setUp(() {
    pinService = _FakePinService();
    friendsService = _FakeFriendsService();
    authState = AuthState()..login(_fakeJwtFor('u1'));
  });

  Widget build() {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebPinnedScreen(authState: authState, pinService: pinService, friendsService: friendsService),
      ),
    );
  }

  // Regression test for #205: on a wide desktop window, PinnedMessageCard's image (rendered
  // via BirdPayloadView at width: double.infinity) used to stretch to the full window width
  // instead of the app's established ~720px content-width convention (see
  // WebProfileScreen), making pin images look huge and out of proportion.
  testWidgets('pin cards are capped to the app content-width convention on a wide window', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pinService.mineToReturn = [_pin('p1', imageUrl: 'https://example.com/pic.jpg')];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    final cardWidth = tester.getSize(find.byKey(const Key('pinnedMessageCard_p1'))).width;
    expect(cardWidth, lessThanOrEqualTo(720));
  });
}
