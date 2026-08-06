import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/screens/sign_up_screen.dart';
import 'package:cro_app/state/auth_state.dart';

void main() {
  testWidgets('shows username, email, and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SignUpScreen(authState: AuthState())));

    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('emailField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
  });
}
