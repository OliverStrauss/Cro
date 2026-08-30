import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // Added for the web shell (dock cards, panel sections, hub-suggestion/admin accents,
  // away-state and success cues) - no existing ColorScheme role fits these cleanly, so
  // they're exposed as raw constants like the rest of this class rather than forced into
  // a ColorScheme slot that doesn't semantically match.
  static const warmSurface = Color(0xFFF4F2ED);
  static const altSurface = Color(0xFFF9F8F5);
  static const amberInk = Color(0xFFA2521F);
  static const success = Color(0xFF4FA97C);
  static const alertAway = Color(0xFFE8714A);
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
  // Quicksand for headings/names/numerals, Inter for body copy - per the web design
  // handoff's typography tokens. Applied to the shared theme (not web-only) since
  // 02_theme_and_palette.md already specs this as a whole-app refresh, not a web-exclusive
  // one; theme_test.dart doesn't assert on font family, so this is additive.
  textTheme: GoogleFonts.interTextTheme().copyWith(
    titleLarge: GoogleFonts.quicksand(fontWeight: FontWeight.w700),
    titleMedium: GoogleFonts.quicksand(fontWeight: FontWeight.w600),
    titleSmall: GoogleFonts.quicksand(fontWeight: FontWeight.w600),
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
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: CroColors.surface,
    height: 78,
    // The 1px top border that visually separates the bar from body content isn't
    // expressible via NavigationBarThemeData - HomeScreen wraps the bar in a Container
    // with that border instead of relying on theme alone.
    elevation: 0,
    indicatorColor: CroColors.waypointBlue.withValues(alpha: 0.18),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: selected ? CroColors.deepWaypoint : CroColors.fog,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? CroColors.waypointBlue : CroColors.fog);
    }),
  ),
);
