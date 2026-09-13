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

  // Pale state-tint backgrounds (dock/nest cards' flight/away/hub-visit rows) - named here
  // instead of left as bare hex literals so they're not silently re-typed per call site.
  static const flightTint = Color(0xFFF5FAFD);
  static const warmTint = Color(0xFFFDF7F0);

  // Hairline rule color used everywhere a divider, card outline, or table row rule replaces
  // the old soft-shadow card edge - see the Radio Log direction contract in
  // .impeccable/surfaces/app-lib-web.md. One alpha, one color, so every hairline in the app
  // reads as the same weight of ink rather than a dozen independently-tuned grays.
  static const hairline = Color(0x242B2F33); // CroColors.ink @ 14%
}

/// The "data voice" and "label voice" for the Radio Log world: every coordinate, distance,
/// timestamp, nav label, badge, chip, and button reads in one tracked monospace face at one
/// of a small number of named sizes, instead of each call site picking its own ad hoc
/// TextStyle. Prose (message bodies, descriptions, dialog copy) stays on the theme's default
/// text theme (IBM Plex Sans) and never calls into this class.
class CroTextStyles {
  CroTextStyles._();

  static TextStyle data({double size = 11.5, Color color = CroColors.fog, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: weight, letterSpacing: 0.2, height: 1.3);

  // Tracked, usually-uppercase short labels: nav items, section headers, chip/badge text,
  // and every hand-rolled "button" that isn't a real ElevatedButton/OutlinedButton/TextButton
  // (those pick this up automatically via ThemeData.textTheme.labelLarge/Medium/Small below).
  static TextStyle label({double size = 11, Color color = CroColors.ink, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: weight, letterSpacing: 0.8, height: 1.1);

  // The hand-stamped "CONFIRMED" mark and its kin - arrival, acceptance, success. Amber stays
  // confined to this and other hairline/edge moments per the direction's color-restraint raise,
  // never a filled background.
  static TextStyle stamp({double size = 10, Color color = CroColors.amberInk}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: FontWeight.w700, letterSpacing: 1.3, height: 1);
}

/// Shared hairline border + corner radius so every hand-rolled Container decoration (map
/// markers, dock cards, panel chrome) draws the same boxy, ruled-ledger edge instead of each
/// widget choosing its own radius/shadow. Real Card/Button/Input widgets get this from
/// ThemeData directly; anything built from a bare Container reaches for these.
class CroBorders {
  CroBorders._();

  static Border hairline({Color color = CroColors.ink, double alpha = 0.14, double width = 1}) =>
      Border.all(color: color.withValues(alpha: alpha), width: width);

  static const radius = BorderRadius.all(Radius.circular(4));
  static const radiusSmall = BorderRadius.all(Radius.circular(3));
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
  // Radio Log world (see .impeccable/surfaces/app-lib-web.md): IBM Plex Sans carries prose,
  // IBM Plex Mono carries every station-log data role - headings read as station/log labels,
  // and label*/* is what every real Button/Chip picks up automatically, so this one change
  // retypes every stock Material control in the app without touching each call site.
  textTheme: GoogleFonts.ibmPlexSansTextTheme().copyWith(
    titleLarge: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w700, letterSpacing: 0.2, color: CroColors.ink),
    titleMedium: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w600, letterSpacing: 0.2, color: CroColors.ink),
    titleSmall: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w600, letterSpacing: 0.3, color: CroColors.ink),
    labelLarge: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w600, letterSpacing: 0.8, color: CroColors.ink),
    labelMedium: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w600, letterSpacing: 0.7, color: CroColors.ink),
    labelSmall: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w600, letterSpacing: 0.6, color: CroColors.fog),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: CroColors.deepWaypoint,
    foregroundColor: CroColors.surface,
    titleTextStyle: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w700, letterSpacing: 0.4, color: CroColors.surface, fontSize: 18),
    elevation: 0,
  ),
  // Hairline card edge instead of Material's soft elevation shadow - a logbook plate, not a
  // floating chip. Elevation 0 everywhere; depth comes from the ruled edge, not a blur.
  cardTheme: CardThemeData(
    color: CroColors.surface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: CroBorders.radius, side: CroBorders.hairline()),
    margin: EdgeInsets.zero,
  ),
  dividerTheme: const DividerThemeData(color: CroColors.hairline, thickness: 1, space: 1),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: CroColors.waypointBlue,
      foregroundColor: CroColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: CroBorders.radius),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: CroColors.ink,
      side: BorderSide(color: CroColors.ink.withValues(alpha: 0.24)),
      shape: RoundedRectangleBorder(borderRadius: CroBorders.radius),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: CroColors.deepWaypoint,
      shape: RoundedRectangleBorder(borderRadius: CroBorders.radius),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: CroColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: CroBorders.radius, borderSide: CroBorders.hairline()),
    enabledBorder: OutlineInputBorder(borderRadius: CroBorders.radius, borderSide: CroBorders.hairline()),
    focusedBorder: OutlineInputBorder(borderRadius: CroBorders.radius, borderSide: const BorderSide(color: CroColors.waypointBlue, width: 1.5)),
    labelStyle: CroTextStyles.data(size: 12.5, color: CroColors.fog),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: CroColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: CroBorders.hairline()),
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(color: CroColors.ink, borderRadius: CroBorders.radiusSmall),
    textStyle: CroTextStyles.label(size: 10.5, color: CroColors.surface, weight: FontWeight.w600),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: CroColors.ink,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: CroBorders.radiusSmall),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: CroColors.waypointBlue,
    foregroundColor: CroColors.surface,
  ),
);
