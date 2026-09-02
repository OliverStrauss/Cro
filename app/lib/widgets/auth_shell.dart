import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import 'cro_logo_mark.dart';

// Shared page chrome for the login/sign-up screens - previously each screen was just a bare
// AppBar over a 320px column of default-styled fields, the one part of the app that never
// picked up the web redesign's palette/card language (everything post-login lives under
// lib/web/ and already has it - see CLAUDE.md's repository-structure note on why these two
// screens still sit directly under lib/screens/). On a wide (>=840px) window - the only kind
// this desktop/web-only app actually runs in - a branding pane sits beside the form card;
// below that width (including this project's default, phone-sized test viewport) it collapses
// to a single centered card so nothing here depends on a real desktop window to render
// correctly.
class AuthShell extends StatelessWidget {
  final String heading;
  final String subheading;
  final Widget child;
  final Widget footer;

  const AuthShell({super.key, required this.heading, required this.subheading, required this.child, required this.footer});

  @override
  Widget build(BuildContext context) {
    final card = _FormCard(heading: heading, subheading: subheading, footer: footer, child: child);
    return Scaffold(
      backgroundColor: CroColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 840) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CroLogoMark(size: 28, color: CroColors.waypointBlue),
                          const SizedBox(width: 10),
                          Text('Cro', style: GoogleFonts.quicksand(fontSize: 22, fontWeight: FontWeight.w700, color: CroColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 28),
                      card,
                    ],
                  ),
                ),
              );
            }
            return Row(
              children: [
                Expanded(flex: 5, child: _BrandingPane()),
                Expanded(
                  flex: 6,
                  child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(40), child: card)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String heading;
  final String subheading;
  final Widget child;
  final Widget footer;

  const _FormCard({required this.heading, required this.subheading, required this.child, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('authCard'),
      width: 400,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: GoogleFonts.quicksand(fontSize: 22, fontWeight: FontWeight.w700, color: CroColors.ink)),
          const SizedBox(height: 6),
          Text(subheading, style: const TextStyle(fontSize: 13, color: CroColors.fog, height: 1.4)),
          const SizedBox(height: 28),
          child,
          const SizedBox(height: 20),
          footer,
        ],
      ),
    );
  }
}

// The gradient panel shown alongside the form on wide windows - wordmark plus a small flight
// illustration (two nest dots joined by a dashed trail, a bird mid-flight) echoing the actual
// map's own dashed-polyline/bird-marker language (see web_map_screen.dart) rather than generic
// hero art, so this reads as unmistakably Cro's own visual identity.
class _BrandingPane extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CroColors.deepWaypoint, CroColors.waypointBlue],
        ),
      ),
      padding: const EdgeInsets.all(56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CroLogoMark(size: 52, color: Colors.white),
          const SizedBox(height: 20),
          Text(
            'Cro',
            style: GoogleFonts.quicksand(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
          ),
          const SizedBox(height: 14),
          const Text(
            'Send a message and watch it travel. Every cro takes real days to\ncross the map before it lands.',
            style: TextStyle(fontSize: 14, color: Colors.white, height: 1.5),
          ),
          const SizedBox(height: 40),
          const _FlightPathGlyph(),
        ],
      ),
    );
  }
}

class _FlightPathGlyph extends StatelessWidget {
  const _FlightPathGlyph();

  Widget _dashedLine() {
    const dashWidth = 5.0, gap = 4.0, totalWidth = 110.0;
    final count = (totalWidth / (dashWidth + gap)).floor();
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : gap),
            child: Container(width: dashWidth, height: 2, color: Colors.white.withValues(alpha: 0.55)),
          ),
      ],
    );
  }

  Widget _dot({required double size, required Color color, Border? border}) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: border));

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(size: 11, color: Colors.white),
        const SizedBox(width: 8),
        _dashedLine(),
        const SizedBox(width: 8),
        _dot(size: 13, color: CroColors.deliveryAmber, border: Border.all(color: Colors.white, width: 1.5)),
        const SizedBox(width: 8),
        _dashedLine(),
        const SizedBox(width: 8),
        _dot(size: 11, color: Colors.white.withValues(alpha: 0.5)),
      ],
    );
  }
}
