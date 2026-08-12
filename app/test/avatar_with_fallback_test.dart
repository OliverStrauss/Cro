import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/widgets/avatar_with_fallback.dart';

void main() {
  testWidgets('borderColor overrides the default theme primary border color', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AvatarWithFallback(
          avatarKey: Key('avatar'),
          imageUrl: null,
          initialsSource: 'Backyard',
          hasBorder: true,
          borderColor: Colors.orange,
        ),
      ),
    ));

    final container = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('avatar')),
      matching: find.byType(Container),
    ));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, Border.all(color: Colors.orange, width: 3));
  });

  testWidgets('falls back to the theme primary color when no borderColor is given', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(primary: Colors.teal)),
      home: const Scaffold(
        body: AvatarWithFallback(
          avatarKey: Key('avatar'),
          imageUrl: null,
          initialsSource: 'Backyard',
          hasBorder: true,
        ),
      ),
    ));

    final container = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('avatar')),
      matching: find.byType(Container),
    ));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, Border.all(color: Colors.teal, width: 3));
  });
}
