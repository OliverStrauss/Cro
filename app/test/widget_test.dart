import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/main.dart';
import 'package:cro_app/state/auth_state.dart';

void main() {
  testWidgets('shows the login screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(authState: AuthState()));

    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
  });

  testWidgets('shows the web shell once AuthState is logged in, on every platform', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MyApp(authState: authState));
    await tester.pump();

    // 'test-token' isn't a real JWT, so the shell's own (real, unfaked) data load fails
    // fast with a decode error rather than resolving - which is fine here, since the point
    // of this test is only that logging in now renders the web shell (not the retired phone
    // HomeScreen) on every platform, not that its data load succeeds.
    expect(find.byKey(const Key('usernameField')), findsNothing);
    expect(find.byKey(const Key('webShellError')), findsOneWidget);
  });
}
