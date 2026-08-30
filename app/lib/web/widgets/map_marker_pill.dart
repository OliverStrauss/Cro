import 'package:flutter/material.dart';

/// The white pill marker shared by nest and Hub map markers - a ringed/tinted avatar plus a
/// name + one-line subtitle, with a colored border when selected. Hub markers pass a larger
/// corner radius (14) than nest markers (30, i.e. fully rounded) per the design spec.
class MapMarkerPill extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String subtitle;
  final bool selected;
  final Color selectionColor;
  final double borderRadius;
  final VoidCallback onTap;

  const MapMarkerPill({
    super.key,
    required this.avatar,
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.selectionColor,
    required this.onTap,
    this.borderRadius = 30,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(borderRadius),
          border: selected ? Border.all(color: selectionColor, width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
