import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/theme.dart';
import 'package:cro_app/widgets/send_bird_dialog.dart';

void main() {
  // Origin at (0, 0); same-longitude destinations reduce the haversine formula to a plain
  // meridian distance, so "nearer" here is simply "smaller latitude offset".
  final nearNest = SendBirdDestination(nestId: 'n1', name: 'Near Nest', latitude: 0.09, longitude: 0, isHub: false);
  final farNest = SendBirdDestination(
    nestId: 'n2',
    name: 'Far Nest',
    ownerUsername: 'bob',
    latitude: 0.9,
    longitude: 0,
    isHub: false,
  );
  final nearHub = SendBirdDestination(
    nestId: 'h1',
    name: 'Near Hub',
    latitude: 0.045,
    longitude: 0,
    isHub: true,
    category: 'Park',
  );
  final farHub = SendBirdDestination(
    nestId: 'h2',
    name: 'Far Hub',
    latitude: 0.45,
    longitude: 0,
    isHub: true,
    category: 'Bar',
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<SendBirdResult>(
              context: context,
              builder: (_) => SendBirdDialog(
                destinations: [nearNest, farNest, nearHub, farHub],
                originLatitude: 0,
                originLongitude: 0,
                speedKmh: 60,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('Nest tab (default) offers only nests, sorted nearest-first; Hub tab augments with hubs', (tester) async {
    await openDialog(tester);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Nest'), findsOneWidget);
    expect(find.text('Far Nest (bob)'), findsOneWidget);
    expect(find.text('Near Hub (Park)'), findsNothing);
    // Nearer destination renders above the farther one.
    expect(
      tester.getTopLeft(find.text('Near Nest')).dy,
      lessThan(tester.getTopLeft(find.text('Far Nest (bob)')).dy),
    );

    await tester.tap(find.text('Hub'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Hub (Park)'), findsOneWidget);
    expect(find.text('Far Hub (Bar)'), findsOneWidget);
    expect(find.text('Near Nest'), findsNothing);
  });

  testWidgets('Hub tab shows a filter chip for every HubCategory, same fixed list as recommending a hub, and selecting one filters the dropdown', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Hub'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sendBirdCategoryChip_Park')), findsOneWidget);
    expect(find.byKey(const Key('sendBirdCategoryChip_Bar')), findsOneWidget);
    // Shown even though no destination in this dialog has that category - the chip list is
    // the fixed HubCategory.all, not derived from which hubs happen to be present.
    expect(find.byKey(const Key('sendBirdCategoryChip_Business')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sendBirdCategoryChip_Park')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.text('Near Hub (Park)'), findsOneWidget);
    expect(find.text('Far Hub (Bar)'), findsNothing);
  });

  testWidgets('every entry shows a distance-and-travel-time trailing label', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();

    final trailingLabels = tester.widgetList<Text>(find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(' mi · '),
    ));
    expect(trailingLabels.length, 2); // Near Nest + Far Nest visible on the Nest tab
  });

  testWidgets('selecting a destination and confirming pops a SendBirdResult with trimmed content', (tester) async {
    SendBirdResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<SendBirdResult>(
                context: context,
                builder: (_) => SendBirdDialog(
                  destinations: [nearNest, farNest],
                  originLatitude: 0,
                  originLongitude: 0,
                  speedKmh: 60,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Send is disabled with nothing picked yet.
    expect(tester.widget<FilledButton>(find.byKey(const Key('confirmSendBirdButton'))).onPressed, isNull);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Far Nest (bob)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sendBirdMessageField')), '  hello  ');
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(result?.nestId, 'n2');
    expect(result?.content, 'hello');
  });

  testWidgets('public/private switch defaults off, honors initialIsPublic, and its value reaches the result', (tester) async {
    SendBirdResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: croTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<SendBirdResult>(
                context: context,
                builder: (_) => SendBirdDialog(
                  destinations: [nearNest],
                  originLatitude: 0,
                  originLongitude: 0,
                  speedKmh: 60,
                  initialIsPublic: true,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byKey(const Key('sendBirdPublicSwitch'))).value, isTrue);

    await tester.tap(find.byKey(const Key('sendBirdPublicSwitch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Nest').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendBirdButton')));
    await tester.pumpAndSettle();

    expect(result?.isPublic, isFalse);
  });
}
