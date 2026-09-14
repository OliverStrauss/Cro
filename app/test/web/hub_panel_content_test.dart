import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cro_app/models/bird.dart';
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

  Widget build(Hub hub, {List<Bird> ownBirds = const [], ValueChanged<Bird>? onSelectBird}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: HubPanelContent(
          hub: hub,
          ownBirds: ownBirds,
          authState: authState,
          onClose: () {},
          hubService: hubService,
          friendsService: friendsService,
          profileService: profileService,
          onSelectBird: onSelectBird ?? (_) {},
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

  testWidgets('a hub with none of the caller\'s birds there hides the "Your birds here" section', (tester) async {
    await tester.pumpWidget(build(hub));
    await tester.pump();

    expect(find.text('Your birds here'), findsNothing);
  });

  testWidgets('a hub with one of the caller\'s own birds there lists it, reusing the resident row', (tester) async {
    // Like a bird already dropped off at this hub - it's landed (not traveling), so it shows
    // up in the caller's own full bird list with currentNestId pointing at the hub's id.
    final myBirdHere = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'h1', isTraveling: false, type: 'Cro');
    // Still flying toward this hub, or resting somewhere else, shouldn't show.
    final stillFlying = Bird(id: 'b2', userId: 'u1', name: 'Percy', isTraveling: true, nestFromId: 'n1', nestToId: 'h1', type: 'Sparrow');
    final elsewhere = Bird(id: 'b3', userId: 'u1', name: 'Fen', currentNestId: 'n1', isTraveling: false, type: 'Cro');

    await tester.pumpWidget(build(hub, ownBirds: [myBirdHere, stillFlying, elsewhere]));
    await tester.pump();

    expect(find.text('Your birds here'), findsOneWidget);
    expect(find.byKey(const Key('hubPanelResident_b1')), findsOneWidget);
    expect(find.text('Otto'), findsOneWidget);
    expect(find.byKey(const Key('hubPanelResident_b2')), findsNothing);
    expect(find.byKey(const Key('hubPanelResident_b3')), findsNothing);
  });

  testWidgets('tapping a resident bird opens its own detail panel instead of a send flow', (tester) async {
    final myBirdHere = Bird(id: 'b1', userId: 'u1', name: 'Otto', currentNestId: 'h1', isTraveling: false, type: 'Cro');
    Bird? selected;

    await tester.pumpWidget(build(hub, ownBirds: [myBirdHere], onSelectBird: (bird) => selected = bird));
    await tester.pump();

    await tester.tap(find.byKey(const Key('hubPanelResident_b1')));
    await tester.pump();

    expect(selected?.id, 'b1');
  });
}
