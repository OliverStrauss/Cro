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

  testWidgets('shows the home screen once AuthState is logged in', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MyApp(authState: authState));

    expect(find.byKey(const Key('usernameField')), findsNothing);
    expect(find.byKey(const Key('homeNavBar')), findsOneWidget);
    expect(find.byKey(const Key('navMap')), findsOneWidget);
    expect(find.byKey(const Key('navFriends')), findsOneWidget);
    expect(find.byKey(const Key('navProfile')), findsOneWidget);
  });
}
