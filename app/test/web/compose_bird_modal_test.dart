import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/theme.dart';
import 'package:cro_app/widgets/compose_bird_dialog.dart';
import 'package:cro_app/widgets/send_bird_dialog.dart';
import 'package:cro_app/web/widgets/compose_bird_modal.dart';

void main() {
  final origins = [SendBirdDestination(nestId: 'n1', label: 'Home Roost')];
  final destinations = [SendBirdDestination(nestId: 'f1', label: "Mia's Cabin (mia)")];

  Widget build({ValueChanged<ComposeBirdResult>? onSubmit}) {
    return MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ComposeBirdModal.show(
              context,
              origins: origins,
              destinations: destinations,
              onSubmit: onSubmit ?? (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the 620px modal with the shared compose form', (tester) async {
    await tester.pumpWidget(build());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composeBirdModal')), findsOneWidget);
    expect(find.text('Send a bird'), findsOneWidget);
    expect(find.byKey(const Key('composeBirdNameField')), findsOneWidget);
    expect(find.text('Release the bird'), findsOneWidget);
  });

  testWidgets('Send is disabled until the form is valid, then submits and closes', (tester) async {
    ComposeBirdResult? submitted;
    await tester.pumpWidget(build(onSubmit: (r) => submitted = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sendButtonFinder = find.byKey(const Key('confirmComposeBirdButton'));
    expect(tester.widget<TextButton>(sendButtonFinder).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('composeBirdNameField')), 'Percy');
    await tester.enterText(find.byKey(const Key('composeBirdContentField')), 'Hello!');
    // Cro only needs one nest for origin (auto-selected) and a destination pick.
    await tester.tap(find.byKey(const Key('composeBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Mia's Cabin (mia)").last);
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(sendButtonFinder).onPressed, isNotNull);

    await tester.tap(sendButtonFinder);
    await tester.pumpAndSettle();

    expect(submitted?.name, 'Percy');
    expect(submitted?.destinationId, 'f1');
    expect(find.byKey(const Key('composeBirdModal')), findsNothing);
  });

  testWidgets('bird type segmented button switches the submitted type', (tester) async {
    ComposeBirdResult? submitted;
    await tester.pumpWidget(build(onSubmit: (r) => submitted = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birdTypeSegmentedButton')), findsOneWidget);
    final button = tester.widget<SegmentedButton<String>>(find.byKey(const Key('birdTypeSegmentedButton')));
    expect(button.selected, {'Cro'});

    await tester.tap(find.text('Raven'));
    await tester.pumpAndSettle();

    // Raven needs both text and an image - only content is filled in here, so Send stays
    // disabled, which is itself evidence the type switch took effect.
    await tester.enterText(find.byKey(const Key('composeBirdNameField')), 'Bramble');
    await tester.enterText(find.byKey(const Key('composeBirdContentField')), 'Note');
    await tester.tap(find.byKey(const Key('composeBirdDestinationDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Mia's Cabin (mia)").last);
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(find.byKey(const Key('confirmComposeBirdButton'))).onPressed, isNull);
    expect(submitted, isNull);
  });

  testWidgets('Cancel closes the modal without submitting', (tester) async {
    var submitted = false;
    await tester.pumpWidget(build(onSubmit: (_) => submitted = true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancelComposeBirdButton')));
    await tester.pumpAndSettle();

    expect(submitted, isFalse);
    expect(find.byKey(const Key('composeBirdModal')), findsNothing);
  });
}
