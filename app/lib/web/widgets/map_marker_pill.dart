import 'package:flutter/material.dart';

import '../../theme.dart';

/// The white pill marker shared by nest and Hub map markers - a ringed/tinted avatar plus a
/// name + one-line subtitle, with a colored border when selected. Both nest and Hub markers
/// pass `compact: true` now (smaller padding/gap/text than the pre-05_web_ui_updates.md
/// default, which read as oversized once seen live) - Hub markers additionally use a smaller
/// `borderRadius` (11, boxier) and avatar than nest markers (default 30, fully rounded) so
/// nests still read as primary.
class MapMarkerPill extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String subtitle;
  final bool selected;
  final Color selectionColor;
  final double borderRadius;
  final bool compact;
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
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: compact ? const EdgeInsets.fromLTRB(5, 5, 10, 5) : const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: CroColors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: selected ? selectionColor : CroColors.hairline, width: selected ? 1.5 : 1),
            boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              SizedBox(width: compact ? 7 : 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CroTextStyles.label(size: compact ? 11.5 : 13, color: CroColors.ink),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CroTextStyles.data(size: compact ? 10 : 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
