import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/hub.dart';
import 'package:cro_app/models/user_profile.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/services/profile_service.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';
import 'package:cro_app/web/screens/web_hubs_screen.dart';

class _FakeHubService implements HubService {
  List<Hub> suggestionsToReturn = [];
  String? lastApprovedId;
  String? lastRejectedId;

  @override
  Future<List<Hub>> listSuggestions(String token) async => suggestionsToReturn;

  @override
  Future<Hub> approveSuggestion(String token, String hubId) async {
    lastApprovedId = hubId;
    return suggestionsToReturn.firstWhere((h) => h.id == hubId);
  }

  @override
  Future<void> rejectSuggestion(String token, String hubId) async {
    lastRejectedId = hubId;
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebHubsScreen');
}

class _FakeProfileService implements ProfileService {
  @override
  Future<UserProfile> getUser(String userId) async =>
      UserProfile(id: userId, username: 'wren_p', email: 'wren@example.com');

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by WebHubsScreen');
}

void main() {
  final hub = Hub(id: 'h1', name: 'Lighthouse Point', latitude: 42, longitude: -93, status: 'Approved', createdByUserId: 'admin', category: 'Landmark');
  final suggestion = Hub(id: 's1', name: 'Harbour Steps', latitude: 41, longitude: -94, status: 'Pending', createdByUserId: 'u9', category: 'Landmark');

  late _FakeHubService hubService;
  late _FakeProfileService profileService;
  late AuthState authState;

  setUp(() {
    hubService = _FakeHubService();
    profileService = _FakeProfileService();
    authState = AuthState()..login('a.b.c');
  });

  Widget build({List<Hub> hubs = const [], bool isAdmin = false, VoidCallback? onDataChanged}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: WebHubsScreen(
          hubs: hubs,
          isAdmin: isAdmin,
          selectedHubId: null,
          onSelectHub: (_) {},
          authState: authState,
          hubService: hubService,
          profileService: profileService,
          onDataChanged: onDataChanged ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows an empty state with no hubs, else a card per hub', (tester) async {
    await tester.pumpWidget(build());
    expect(find.byKey(const Key('noHubsMessage')), findsOneWidget);

    await tester.pumpWidget(build(hubs: [hub]));
    expect(find.byKey(const Key('webHubCard_h1')), findsOneWidget);
    expect(find.text('Lighthouse Point'), findsOneWidget);
  });

  testWidgets('non-admins never see the suggested-hubs queue', (tester) async {
    await tester.pumpWidget(build(hubs: [hub]));
    expect(find.text('Suggested hubs'), findsNothing);
  });

  testWidgets('admins see the suggested-hubs queue with the suggester resolved', (tester) async {
    hubService.suggestionsToReturn = [suggestion];
    await tester.pumpWidget(build(isAdmin: true));
    await tester.pumpAndSettle();

    expect(find.text('Suggested hubs'), findsOneWidget);
    expect(find.byKey(const Key('hubSuggestion_s1')), findsOneWidget);
    expect(find.textContaining('Suggested by wren_p'), findsOneWidget);
  });

  testWidgets('approving a suggestion calls the service and refreshes', (tester) async {
    hubService.suggestionsToReturn = [suggestion];
    var changed = false;
    await tester.pumpWidget(build(isAdmin: true, onDataChanged: () => changed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approveSuggestionButton_s1')));
    await tester.pumpAndSettle();

    expect(hubService.lastApprovedId, 's1');
    expect(changed, isTrue);
  });

  testWidgets('rejecting a suggestion requires two taps to confirm', (tester) async {
    hubService.suggestionsToReturn = [suggestion];
    await tester.pumpWidget(build(isAdmin: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rejectSuggestionButton_s1')));
    await tester.pump();
    expect(find.text('Confirm?'), findsOneWidget);
    expect(hubService.lastRejectedId, isNull);

    await tester.tap(find.byKey(const Key('rejectSuggestionButton_s1')));
    await tester.pumpAndSettle();
    expect(hubService.lastRejectedId, 's1');
  });
}
