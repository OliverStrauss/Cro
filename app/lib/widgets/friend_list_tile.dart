import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../theme.dart';
import '../utils/color_utils.dart';
import 'avatar_with_fallback.dart';

// A fixed-width vertical card - not a "tile" anymore, but kept the name to avoid
// churning every import across the social screen and its tests. Stateless: every value
// shown is derived straight from `friend`, nothing here is mutated locally.
class FriendListTile extends StatelessWidget {
  final Friend friend;
  final ValueChanged<String>? onColorSelected;

  const FriendListTile({super.key, required this.friend, this.onColorSelected});

  // The friend's assigned trail color rings their avatar - this is the one place in the
  // app that shows a friend's color outside the map itself, so it should visibly match
  // their flight-path color there. Falls back to fog for the (legacy/pre-color-picker)
  // case of a friend with no color assigned yet.
  Color get _ringColor =>
      friend.color != null ? hexToColor(friend.color!) : CroColors.fog;

  Future<void> _pickColor(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a color'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final hex in friendColorPalette)
                  InkWell(
                    key: Key('colorOption_$hex'),
                    onTap: () => Navigator.of(context).pop(hex),
                    child: CircleAvatar(
                      backgroundColor: hexToColor(hex),
                      radius: 16,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      onColorSelected?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('friendTile_${friend.userId}'),
      onTap: onColorSelected == null ? null : () => _pickColor(context),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWithFallback(
              avatarKey: Key('friendAvatar_${friend.userId}'),
              imageUrl: friend.profilePictureUrl,
              initialsSource: friend.username,
              radius: 28,
              hasBorder: true,
              borderColor: _ringColor,
            ),
            const SizedBox(height: 6),
            Text(
              friend.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CroColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
