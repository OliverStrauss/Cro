import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/screens/profile_screen.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/state/auth_state.dart';

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

// A syntactically valid (unsigned) JWT with the given subject - ProfileScreen decodes
// this client-side to know which user id to fetch.
String _fakeJwtFor(String userId) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({
        'alg': 'HS256'
      })}.${segment({
        'sub': userId
      })}.sig';
}

void main() {
  testWidgets('shows loading indicator before the profile loads', (WidgetTester tester) async {
    final fakeService = _FakeProfileService();
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));

    expect(find.byKey(const Key('profileLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows the username once loaded', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()
      ..profileToReturn = UserProfile(id: 'u1', username: 'alice', email: 'alice@example.com');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('shows an error and retry button on failure', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()..loadErrorToThrow = ProfileException('Could not load profile');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileErrorState')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Sign Out is tappable even when the profile fails to load', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()..loadErrorToThrow = ProfileException('Could not load profile');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logoutButton')));

    expect(authState.isLoggedIn, isFalse);
  });

  testWidgets('picking and uploading a picture refetches the profile', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()
      ..profileToReturn = UserProfile(id: 'u1', username: 'alice', email: 'alice@example.com')
      ..imageToReturn = XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'avatar.png', mimeType: 'image/png');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastUploadedFilename, 'avatar.png');
    expect(fakeService.lastUploadedContentType, 'image/png');
    expect(find.text('Profile picture updated'), findsOneWidget);
  });

  testWidgets('canceling the image picker does not attempt an upload', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()
      ..profileToReturn = UserProfile(id: 'u1', username: 'alice', email: 'alice@example.com')
      ..imageToReturn = null;
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(fakeService.lastUploadedFilename, isNull);
  });

  testWidgets('shows an error toast when the upload fails', (WidgetTester tester) async {
    final fakeService = _FakeProfileService()
      ..profileToReturn = UserProfile(id: 'u1', username: 'alice', email: 'alice@example.com')
      ..imageToReturn = XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'avatar.png', mimeType: 'image/png')
      ..uploadErrorToThrow = ProfileException('Could not upload profile picture');
    final authState = AuthState()..login(_fakeJwtFor('u1'));
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(authState: authState, profileService: fakeService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();

    expect(find.text('Could not upload profile picture'), findsOneWidget);
  });
}
