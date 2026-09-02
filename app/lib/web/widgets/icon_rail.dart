import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../state/web_shell_controller.dart';

/// The 76px icon rail: logo, Map/Nests/Hubs/Friends/You nav (no Birds item - the dock
/// replaces it), avatar pinned at the bottom. Deliberately has no "Send a bird"/notification
/// affordance of its own - those live in TopBar.
class IconRail extends StatelessWidget {
  final WebNavItem selected;
  final ValueChanged<WebNavItem> onSelect;
  final int nestsBadge;
  final int friendsBadge;
  final String? profilePictureUrl;
  final String initialsSource;
  final VoidCallback onAvatarTap;

  const IconRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.nestsBadge,
    required this.friendsBadge,
    required this.profilePictureUrl,
    required this.initialsSource,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      color: CroColors.deepWaypoint,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Transform.rotate(
            angle: -0.78,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: CroColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(17),
                  topRight: Radius.circular(17),
                  bottomLeft: Radius.circular(17),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _RailItem(
            key: const Key('webNavMap'),
            icon: Icons.map_rounded,
            label: 'Map',
            selected: selected == WebNavItem.map,
            onTap: () => onSelect(WebNavItem.map),
          ),
          _RailItem(
            key: const Key('webNavNests'),
            icon: Icons.holiday_village_rounded,
            label: 'Nests',
            selected: selected == WebNavItem.nests,
            badge: nestsBadge,
            onTap: () => onSelect(WebNavItem.nests),
          ),
          _RailItem(
            key: const Key('webNavHubs'),
            icon: Icons.location_city_rounded,
            label: 'Hubs',
            selected: selected == WebNavItem.hubs,
            onTap: () => onSelect(WebNavItem.hubs),
          ),
          _RailItem(
            key: const Key('webNavFriends'),
            icon: Icons.people_alt_rounded,
            label: 'Friends',
            selected: selected == WebNavItem.friends,
            badge: friendsBadge,
            onTap: () => onSelect(WebNavItem.friends),
          ),
          _RailItem(
            key: const Key('webNavYou'),
            icon: Icons.person_rounded,
            label: 'You',
            selected: selected == WebNavItem.you,
            onTap: () => onSelect(WebNavItem.you),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Tooltip(
              message: 'Your profile',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('webAvatarButton'),
                  customBorder: const CircleBorder(),
                  onTap: onAvatarTap,
                  child: AvatarWithFallback(
                    imageUrl: profilePictureUrl,
                    initialsSource: initialsSource,
                    radius: 21,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? CroColors.surface : CroColors.surface.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? CroColors.surface.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ],
                ),
                if (badge > 0)
                  Positioned(
                    top: 4,
                    right: 6,
                    child: Container(
                      key: Key('railBadge_$label'),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                      decoration: BoxDecoration(
                        color: CroColors.alertAway,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: CroColors.surface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
