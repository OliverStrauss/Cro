import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/theme.dart';
import 'package:cro_app/web/models/event.dart';
import 'package:cro_app/web/widgets/journey_log_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(theme: croTheme, home: Scaffold(body: child));

  testWidgets('shows a loading indicator', (tester) async {
    await tester.pumpWidget(wrap(JourneyLogPanel(events: const [], isLoading: true, errorMessage: null, onRetry: () {})));
    expect(find.byKey(const Key('journeyLogLoading')), findsOneWidget);
  });

  testWidgets('shows an error state with Retry, which calls onRetry', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(JourneyLogPanel(
      events: const [],
      isLoading: false,
      errorMessage: 'Could not load the journey log',
      onRetry: () => retried = true,
    )));
    expect(find.byKey(const Key('journeyLogError')), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('shows an empty state when there are no events yet', (tester) async {
    await tester.pumpWidget(wrap(JourneyLogPanel(events: const [], isLoading: false, errorMessage: null, onRetry: () {})));
    expect(find.byKey(const Key('journeyLogEmpty')), findsOneWidget);
  });

  testWidgets('lists every event with its quoted note, newest entries included', (tester) async {
    final events = [
      AppEvent(
        id: 'e1',
        kind: EventKind.hubPostCreated,
        displayText: 'Fen posted to the Lighthouse Point board',
        quotedNote: 'Anyone else keeping a perch out here?',
        isNotification: false,
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      AppEvent(
        id: 'e2',
        kind: EventKind.birdJoinedFlock,
        displayText: 'Willa joined your flock',
        isNotification: false,
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
      ),
    ];

    await tester.pumpWidget(wrap(JourneyLogPanel(events: events, isLoading: false, errorMessage: null, onRetry: () {})));

    expect(find.byKey(const Key('journeyEntry_e1')), findsOneWidget);
    expect(find.byKey(const Key('journeyEntry_e2')), findsOneWidget);
    expect(find.text('Fen posted to the Lighthouse Point board'), findsOneWidget);
    expect(find.text('"Anyone else keeping a perch out here?"'), findsOneWidget);
    expect(find.text('Willa joined your flock'), findsOneWidget);
  });
}
