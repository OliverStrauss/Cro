import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../utils/color_utils.dart';
import 'avatar_with_fallback.dart';

class FriendListTile extends StatefulWidget {
  final Friend friend;
  final ValueChanged<String>? onColorSelected;

  const FriendListTile({super.key, required this.friend, this.onColorSelected});

  @override
  State<FriendListTile> createState() => _FriendListTileState();
}

class _FriendListTileState extends State<FriendListTile> {
  Friend get _friend => widget.friend;

  Color get _backgroundColor => _friend.color != null ? hexToColor(_friend.color!) : Colors.grey;

  // Palette colors span light and dark, so pick readable text per-tile rather than a
  // single fixed color.
  Color get _textColor => _backgroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

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
      widget.onColorSelected?.call(selected);
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
          key: Key('friendTile_${_friend.userId}'),
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onColorSelected == null ? null : () => _pickColor(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                AvatarWithFallback(
                  avatarKey: Key('friendAvatar_${_friend.userId}'),
                  imageUrl: _friend.profilePictureUrl,
                  initialsSource: _friend.username,
                  radius: 16,
                ),
                const SizedBox(width: 12),
                Text(
                  _friend.username,
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
