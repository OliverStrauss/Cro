import 'package:flutter/material.dart';

import '../theme.dart';

// Marks an account as an AI bot. Same hairline "stamp" shape as the Admin badge but Deep waypoint,
// not amber - amber is reserved for admin/confirmed moments (see DESIGN.md), and a bot label
// should read as neutral information, not a status flourish.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Automated AI account',
      child: Container(
        key: const Key('botBadge'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: CroBorders.hairline(color: CroColors.deepWaypoint, alpha: 0.6),
          borderRadius: CroBorders.radiusSmall,
        ),
        child: Text('BOT', style: CroTextStyles.stamp(size: 9.5, color: CroColors.deepWaypoint)),
      ),
    );
  }
}
