import 'package:flutter/material.dart';

import '../../theme.dart';

/// Locates the signed-in user's own nest on the map - same 40px trigger-tile treatment as
/// SearchTrigger/FloatingActionsCluster, its neighbors in the floating top-right row.
class NestLocatorButton extends StatelessWidget {
  final VoidCallback onTap;

  const NestLocatorButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: CroBorders.radius, border: Border.all(color: CroColors.hairline)),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        child: InkWell(
          key: const Key('webNestLocatorButton'),
          borderRadius: CroBorders.radius,
          onTap: onTap,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Tooltip(
              message: 'Locate your nest',
              child: Icon(Icons.my_location, size: 19, color: CroColors.fog),
            ),
          ),
        ),
      ),
    );
  }
}
