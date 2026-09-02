import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared header row for every context-panel body (nest/hub/bird detail): avatar, title +
/// subtitle, an optional chip below the subtitle (only the bird panel uses this, for its
/// state badge), and a close (×) button back to the journey log.
class PanelHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  final Widget? chip;
  final VoidCallback onClose;

  const PanelHeader({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.chip,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: CroColors.fog)),
                if (chip != null) ...[const SizedBox(height: 7), chip!],
              ],
            ),
          ),
          Tooltip(
            message: 'Close',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const Key('webPanelClose'),
                customBorder: const CircleBorder(),
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 18, color: CroColors.fog),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
