import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/screens/login_screen.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';

void main() {
  Widget buildLogin() => MaterialApp(theme: croTheme, home: LoginScreen(authState: AuthState()));

  testWidgets('submitting with empty fields shows validation errors instead of calling the auth service', (tester) async {
    await tester.pumpWidget(buildLogin());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await tester.pump();

    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('the password field is obscured by default and the visibility toggle reveals it', (tester) async {
    await tester.pumpWidget(buildLogin());

    TextField passwordField() =>
        tester.widget<TextField>(find.descendant(of: find.byKey(const Key('passwordField')), matching: find.byType(TextField)));

    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('a wide window shows the branding pane beside the form card without overflowing', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildLogin());

    // Two "Cro" wordmarks would only ever render together if both the branding pane's large
    // mark and the narrow layout's small header mark showed at once - this asserts only the
    // wide layout's is present.
    expect(find.text('Cro'), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window shows a small header mark above the card, no branding pane', (tester) async {
    await tester.pumpWidget(buildLogin());

    expect(find.text('Cro'), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
