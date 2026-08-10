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

  testWidgets('the app smoke-pumps with croTheme applied', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(authState: AuthState()));

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme, croTheme);
  });
}
