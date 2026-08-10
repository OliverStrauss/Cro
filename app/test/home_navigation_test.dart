import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/screens/home_screen.dart';
import 'package:cro_app/screens/map_screen.dart';
import 'package:cro_app/state/auth_state.dart';

void main() {
  testWidgets('defaults to the Profile tab', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    final navBar = tester.widget<NavigationBar>(find.byKey(const Key('homeNavBar')));
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('tapping a destination updates the selected tab', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    await tester.tap(find.byKey(const Key('navMap')));
    // Switching to Map now also starts MapScreen's live-update Timer.periodic, so
    // pumpAndSettle() (which waits for no more frames to be scheduled) would hang here
    // forever - a single pump() is enough since the assertion below reads the
    // NavigationBar widget's constructor arg directly, not painted/animated state.
    await tester.pump();

    final navBar = tester.widget<NavigationBar>(find.byKey(const Key('homeNavBar')));
    expect(navBar.selectedIndex, 1);

    // Stop the timer this test started, or it fails at teardown with a "pending timer"
    // error.
    tester.state<MapScreenState>(find.byType(MapScreen)).stopLiveUpdates();
  });

  testWidgets('tapping the Birds destination selects it', (WidgetTester tester) async {
    final authState = AuthState()..login('test-token');
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authState: authState)));

    await tester.tap(find.byKey(const Key('navBirds')));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(find.byKey(const Key('homeNavBar')));
    expect(navBar.selectedIndex, 2);
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
