import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/main.dart';
import 'package:cro_app/state/auth_state.dart';

void main() {
  testWidgets('navigates from Login to Sign Up and back', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(authState: AuthState()));

    expect(find.byKey(const Key('emailField')), findsNothing);

    await tester.tap(find.byKey(const Key('goToSignUpButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('emailField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);

    await tester.tap(find.byKey(const Key('goToLoginButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emailField')), findsNothing);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
  });
}
