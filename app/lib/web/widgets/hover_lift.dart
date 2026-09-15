import 'package:flutter/material.dart';

/// Shared hover polish for an otherwise-flat interactive row/card: a slight scale bump plus
/// whatever the builder does with the hover flag (typically bumping a Material's elevation).
/// A plain MouseRegion + AnimatedScale wrapper - no-op on touch (MouseRegion just never
/// fires), so nothing platform-specific is needed.
class HoverLift extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovering) builder;

  const HoverLift({super.key, required this.builder});

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.builder(context, _hovering),
      ),
    );
  }
}
