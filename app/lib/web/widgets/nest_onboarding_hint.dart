import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shown near the search bar for an account with no own nest yet, urging them to use search
/// to place one - the search-bar entry point (SearchTrigger -> WebMapScreen's search-result
/// banner) is otherwise not discoverable on a first visit. Dismissal is session-only UI state
/// owned by WebShellScreenState (see _nestOnboardingDismissed) - there's no "freshly signed
/// up" flag in the backend to key off, so a nestless account is the proxy signal instead.
class NestOnboardingHint extends StatelessWidget {
  final VoidCallback onDismiss;

  const NestOnboardingHint({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('webNestOnboardingHint'),
      width: 260,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.waypointBlue),
        boxShadow: [
          BoxShadow(color: CroColors.ink.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Search for a place above to place your first nest',
              style: CroTextStyles.data(size: 12.5, color: CroColors.ink, weight: FontWeight.w500),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('webDismissNestOnboardingHint'),
              borderRadius: CroBorders.radiusSmall,
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 15, color: CroColors.fog),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
