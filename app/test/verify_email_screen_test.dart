import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/screens/verify_email_screen.dart';

void main() {
  testWidgets('without an initial email, shows only the email field and a "Send code" button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VerifyEmailScreen()));

    expect(find.byKey(const Key('emailField')), findsOneWidget);
    expect(find.byKey(const Key('codeField')), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Send code'), findsOneWidget);
  });

  testWidgets('with an initial email, skips straight to the code step', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VerifyEmailScreen(initialEmail: 'someone@example.com')));

    expect(find.byKey(const Key('codeField')), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Verify'), findsOneWidget);
    expect(find.byKey(const Key('resendCodeButton')), findsOneWidget);
  });
}
