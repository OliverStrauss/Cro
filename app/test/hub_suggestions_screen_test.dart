import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/hub.dart';
import 'package:cro_app/screens/hub_suggestions_screen.dart';
import 'package:cro_app/services/hub_service.dart';
import 'package:cro_app/state/auth_state.dart';

class _FakeHubService implements HubService {
  List<Hub> suggestionsToReturn = [];
  Object? loadErrorToThrow;
  String? lastApprovedId;
  String? lastRejectedId;

  @override
  Future<List<Hub>> listSuggestions(String token) async {
    if (loadErrorToThrow != null) throw loadErrorToThrow!;
    return suggestionsToReturn;
  }

  @override
  Future<Hub> approveSuggestion(String token, String hubId) async {
    lastApprovedId = hubId;
    final suggestion = suggestionsToReturn.firstWhere((s) => s.id == hubId);
    suggestionsToReturn = suggestionsToReturn.where((s) => s.id != hubId).toList();
    return Hub(
      id: suggestion.id,
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      status: 'Approved',
      createdByUserId: suggestion.createdByUserId,
    );
  }

  @override
  Future<void> rejectSuggestion(String token, String hubId) async {
    lastRejectedId = hubId;
    suggestionsToReturn = suggestionsToReturn.where((s) => s.id != hubId).toList();
  }

  @override
  Future<dynamic> noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by HubSuggestionsScreen');
}

// A syntactically valid (unsigned) JWT - HubSuggestionsScreen never decodes it itself, but
// AuthState.login requires a well-formed token to set a non-null .token.
String _fakeJwt() => 'header.payload.signature';

void main() {
  testWidgets('shows a loading indicator before suggestions load', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwt());
    await tester.pumpWidget(MaterialApp(
      home: HubSuggestionsScreen(authState: authState, hubService: _FakeHubService()),
    ));

    expect(find.byKey(const Key('hubSuggestionsLoadingIndicator')), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no pending suggestions', (WidgetTester tester) async {
    final authState = AuthState()..login(_fakeJwt());
    await tester.pumpWidget(MaterialApp(
      home: HubSuggestionsScreen(authState: authState, hubService: _FakeHubService()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noHubSuggestionsMessage')), findsOneWidget);
  });

  testWidgets('renders each suggestion with its name and coordinates', (WidgetTester tester) async {
    final fakeHubService = _FakeHubService()
      ..suggestionsToReturn = [
        Hub(
          id: 's1',
          name: 'Suggested Park',
          latitude: 42.05,
          longitude: -93.6,
          status: 'Pending',
          createdByUserId: 'u2',
        ),
      ];
    final authState = AuthState()..login(_fakeJwt());
    await tester.pumpWidget(MaterialApp(
      home: HubSuggestionsScreen(authState: authState, hubService: fakeHubService),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hubSuggestion_s1')), findsOneWidget);
    expect(find.text('Suggested Park'), findsOneWidget);
    expect(find.text('(42.0500, -93.6000)'), findsOneWidget);
  });

  testWidgets('approving a suggestion calls the service and removes it from the list', (WidgetTester tester) async {
    final fakeHubService = _FakeHubService()
      ..suggestionsToReturn = [
        Hub(
          id: 's1',
          name: 'Suggested Park',
          latitude: 42.05,
          longitude: -93.6,
          status: 'Pending',
          createdByUserId: 'u2',
        ),
      ];
    final authState = AuthState()..login(_fakeJwt());
    await tester.pumpWidget(MaterialApp(
      home: HubSuggestionsScreen(authState: authState, hubService: fakeHubService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approveSuggestionButton_s1')));
    await tester.pumpAndSettle();

    expect(fakeHubService.lastApprovedId, 's1');
    expect(find.byKey(const Key('hubSuggestion_s1')), findsNothing);
    expect(find.byKey(const Key('noHubSuggestionsMessage')), findsOneWidget);
  });

  testWidgets('rejecting a suggestion requires a second confirming tap', (WidgetTester tester) async {
    final fakeHubService = _FakeHubService()
      ..suggestionsToReturn = [
        Hub(
          id: 's1',
          name: 'Suggested Park',
          latitude: 42.05,
          longitude: -93.6,
          status: 'Pending',
          createdByUserId: 'u2',
        ),
      ];
    final authState = AuthState()..login(_fakeJwt());
    await tester.pumpWidget(MaterialApp(
      home: HubSuggestionsScreen(authState: authState, hubService: fakeHubService),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rejectSuggestionButton_s1')));
    await tester.pumpAndSettle();
    expect(fakeHubService.lastRejectedId, isNull);
    expect(find.text('Confirm?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rejectSuggestionButton_s1')));
    await tester.pumpAndSettle();

    expect(fakeHubService.lastRejectedId, 's1');
    expect(find.byKey(const Key('hubSuggestion_s1')), findsNothing);
  });
}
