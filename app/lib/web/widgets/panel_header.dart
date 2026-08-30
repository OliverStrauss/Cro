import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared header row for every context-panel body (nest/hub/bird detail): avatar, title +
/// subtitle, and a close (×) button back to the journey log.
class PanelHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const PanelHeader({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
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
              ],
            ),
          ),
          GestureDetector(
            key: const Key('webPanelClose'),
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: CroColors.fog),
          ),
        ],
      ),
    );
  }
}
