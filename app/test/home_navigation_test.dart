import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/screens/home_screen.dart';
import 'package:cro_app/state/auth_state.dart';

void main() {
  testWidgets('defaults to the Map tab', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    final navBar = tester.widget<NavigationBar>(find.byKey(const Key('homeNavBar')));
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('tapping a destination updates the selected tab', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    await tester.tap(find.byKey(const Key('navFriends')));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(find.byKey(const Key('homeNavBar')));
    expect(navBar.selectedIndex, 1);
  });

  testWidgets('logging out from Profile actually logs out', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    await tester.tap(find.byKey(const Key('navProfile')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pumpAndSettle();

    expect(authState.isLoggedIn, isFalse);
  });
}
