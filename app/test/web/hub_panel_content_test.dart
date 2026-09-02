import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cro_app/models/friend.dart';
import 'package:cro_app/models/friend_request.dart';
import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/hub_category.dart';
import 'package:cro_app/models/hub_message.dart';
import 'package:cro_app/models/hub_picture_suggestion.dart';
import 'package:cro_app/services/friends_service.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/widgets/hub_panel_content.dart';
import 'package:cro_app/widgets/avatar_with_fallback.dart';

class _FakeHubService implements HubService {
  List<HubMessage> messagesToReturn = [];
  Exception? suggestPictureError;
  String? lastSuggestedPictureHubId;

  @override
  Future<List<HubMessage>> listMessages(String token, String hubId) async => messagesToReturn;

  @override
  Future<HubPictureSuggestion> suggestHubPicture(
    String token,
    String hubId,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    lastSuggestedPictureHubId = hubId;
    if (suggestPictureError != null) throw suggestPictureError!;
    return HubPictureSuggestion(id: 'ps1', hubId: hubId, suggestedByUserId: 'u1', blobUrl: 'https://example.com/p.jpg', createdAt: DateTime(2026));
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by HubPanelContent');
}

class _FakeFriendsService implements FriendsService {
  @override
  Future<List<Friend>> getFriends(String token) async => [];

  @override
  Future<List<FriendRequest>> getIncomingRequests(String token) async => [];

  @override
  Future<List<FriendRequest>> getOutgoingRequests(String token) async => [];

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by HubPanelContent');
}

class _FakeProfileService implements ProfileService {
  XFile? imageToPick;

  @override
  Future<XFile?> pickImage() async => imageToPick;

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by HubPanelContent');
}

void main() {
  final authState = AuthState()..login('a.b.c');

  late _FakeHubService hubService;
  late _FakeFriendsService friendsService;
  late _FakeProfileService profileService;

  setUp(() {
    hubService = _FakeHubService();
    friendsService = _FakeFriendsService();
    profileService = _FakeProfileService();
  });

  Widget build(Hub hub) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: HubPanelContent(
          hub: hub,
          authState: authState,
          onClose: () {},
          hubService: hubService,
          friendsService: friendsService,
          profileService: profileService,
        ),
      ),
    );
  }

  final hub = Hub(id: 'h1', name: 'Lighthouse Point', latitude: 42, longitude: -93, status: 'Approved', createdByUserId: 'admin', category: HubCategory.park);

  testWidgets('no profilePictureUrl shows the category icon fallback', (tester) async {
    await tester.pumpWidget(build(hub));
    await tester.pump();

    expect(find.byIcon(HubCategory.iconFor(HubCategory.park)), findsOneWidget);
    final avatar = tester.widget<AvatarWithFallback>(find.byType(AvatarWithFallback));
    expect(avatar.imageUrl, isNull);
  });

  testWidgets('profilePictureUrl set is passed through to the avatar', (tester) async {
    final photoHub = Hub(
      id: 'h1',
      name: 'Lighthouse Point',
      latitude: 42,
      longitude: -93,
      status: 'Approved',
      createdByUserId: 'admin',
      category: HubCategory.park,
      profilePictureUrl: 'https://example.com/lighthouse.jpg',
    );
    await tester.pumpWidget(build(photoHub));
    await tester.pump();

    final avatar = tester.widget<AvatarWithFallback>(find.byType(AvatarWithFallback));
    expect(avatar.imageUrl, 'https://example.com/lighthouse.jpg');
  });

  testWidgets('the hub name is shown below the avatar circle', (tester) async {
    await tester.pumpWidget(build(hub));
    await tester.pump();

    expect(find.text('Lighthouse Point'), findsOneWidget);
  });

  testWidgets('tapping the suggest-photo button uploads and shows a pending-approval toast', (tester) async {
    profileService.imageToPick = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'photo.jpg', mimeType: 'image/jpeg');

    await tester.pumpWidget(build(hub));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webSuggestHubPictureButton')));
    await tester.pumpAndSettle();

    expect(hubService.lastSuggestedPictureHubId, 'h1');
    expect(find.textContaining('pending admin approval'), findsOneWidget);
  });

  testWidgets('a failed upload shows an error toast and resets the uploading state', (tester) async {
    profileService.imageToPick = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'photo.jpg', mimeType: 'image/jpeg');
    hubService.suggestPictureError = HubException('Could not suggest a photo');

    await tester.pumpWidget(build(hub));
    await tester.pump();

    await tester.tap(find.byKey(const Key('webSuggestHubPictureButton')));
    await tester.pumpAndSettle();

    expect(find.text('Could not suggest a photo'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
