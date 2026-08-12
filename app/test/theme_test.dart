import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/main.dart';
import 'package:cro_app/state/auth_state.dart';
import 'package:cro_app/theme.dart';

void main() {
  test('croTheme maps every palette hex to its documented ColorScheme role', () {
    final scheme = croTheme.colorScheme;

    expect(croTheme.scaffoldBackgroundColor, CroColors.background);
    expect(scheme.surface, CroColors.surface);
    expect(scheme.primary, CroColors.waypointBlue);
    expect(scheme.secondary, CroColors.deepWaypoint);
    expect(scheme.primaryContainer, CroColors.skyTint);
    expect(scheme.onSurface, CroColors.ink);
    expect(scheme.onSurfaceVariant, CroColors.fog);
    expect(scheme.tertiary, CroColors.deliveryAmber);
  });

  test('croTheme themes the app bar and FAB with the deep waypoint / waypoint blue roles', () {
    expect(croTheme.appBarTheme.backgroundColor, CroColors.deepWaypoint);
    expect(croTheme.floatingActionButtonTheme.backgroundColor, CroColors.waypointBlue);
  });

  test('croTheme themes the bottom nav bar with a waypoint-blue pill indicator', () {
    final navTheme = croTheme.navigationBarTheme;
    expect(navTheme.backgroundColor, CroColors.surface);
    expect(navTheme.height, 78);
    expect(navTheme.indicatorColor, CroColors.waypointBlue.withValues(alpha: 0.18));

    final selectedLabel = navTheme.labelTextStyle!.resolve({WidgetState.selected})!;
    expect(selectedLabel.color, CroColors.deepWaypoint);
    final unselectedLabel = navTheme.labelTextStyle!.resolve({})!;
    expect(unselectedLabel.color, CroColors.fog);

    final selectedIcon = navTheme.iconTheme!.resolve({WidgetState.selected})!;
    expect(selectedIcon.color, CroColors.waypointBlue);
    final unselectedIcon = navTheme.iconTheme!.resolve({})!;
    expect(unselectedIcon.color, CroColors.fog);
  });

  testWidgets('the app smoke-pumps with croTheme applied', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(authState: AuthState()));

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme, croTheme);
  });
}
