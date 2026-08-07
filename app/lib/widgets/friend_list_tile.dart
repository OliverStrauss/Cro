import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../utils/color_utils.dart';

class FriendListTile extends StatelessWidget {
  final Friend friend;
  final ValueChanged<String>? onColorSelected;

  const FriendListTile({super.key, required this.friend, this.onColorSelected});

  Color get _backgroundColor => friend.color != null ? hexToColor(friend.color!) : Colors.grey;

  // Palette colors span light and dark, so pick readable text per-tile rather than a
  // single fixed color.
  Color get _textColor => _backgroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  String get _initials {
    final trimmed = friend.username.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

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
                    child: CircleAvatar(backgroundColor: hexToColor(hex), radius: 16),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('friendTile_${friend.userId}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onColorSelected == null ? null : () => _pickColor(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  key: Key('friendAvatar_${friend.userId}'),
                  radius: 16,
                  backgroundImage: friend.profilePictureUrl != null
                      ? NetworkImage(friend.profilePictureUrl!)
                      : null,
                  child: friend.profilePictureUrl == null ? Text(_initials) : null,
                ),
                const SizedBox(width: 12),
                Text(
                  friend.username,
                  style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
