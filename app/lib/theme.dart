import 'package:flutter/material.dart';

// The 8-hex brand palette (see CLAUDE.md's "UI theme / color palette" section for the
// role-mapping rationale). Exposed as raw constants for the handful of call sites that need
// a literal rather than a ColorScheme role - e.g. a nest's own-user border is always this
// exact blue, never a computed/derived tone.
class CroColors {
  CroColors._();

  // A darker, more clearly grey canvas than the original near-white spec - a light blend
  // of Fog with white (roughly 30% Fog) rather than a flat near-white, per explicit
  // preference for Fog's grey to read through the app background, not just secondary text.
  static const background = Color(0xFFD4D7DC);
  static const surface = Color(0xFFFFFFFF);
  static const waypointBlue = Color(0xFF5CB6E3);
  static const deepWaypoint = Color(0xFF2A7194);
  static const skyTint = Color(0xFFBFE4F4);
  static const ink = Color(0xFF2B2F33);
  static const fog = Color(0xFF6B7280);
  static const deliveryAmber = Color(0xFFF3AA5E);
}

final ThemeData croTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: CroColors.background,
  colorScheme: const ColorScheme.light(
    surface: CroColors.surface,
    primary: CroColors.waypointBlue,
    onPrimary: CroColors.surface,
    secondary: CroColors.deepWaypoint,
    onSecondary: CroColors.surface,
    primaryContainer: CroColors.skyTint,
    onPrimaryContainer: CroColors.ink,
    tertiary: CroColors.deliveryAmber,
    onTertiary: CroColors.ink,
    onSurface: CroColors.ink,
    onSurfaceVariant: CroColors.fog,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: CroColors.deepWaypoint,
    foregroundColor: CroColors.surface,
  ),
  cardTheme: const CardThemeData(
    color: CroColors.surface,
    elevation: 1,
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: CroColors.waypointBlue,
    foregroundColor: CroColors.surface,
  ),
);
