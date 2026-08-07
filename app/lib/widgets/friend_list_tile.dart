import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../utils/color_utils.dart';

class FriendListTile extends StatefulWidget {
  final Friend friend;
  final ValueChanged<String>? onColorSelected;

  const FriendListTile({super.key, required this.friend, this.onColorSelected});

  @override
  State<FriendListTile> createState() => _FriendListTileState();
}

class _FriendListTileState extends State<FriendListTile> {
  bool _pictureFailedToLoad = false;

  Friend get _friend => widget.friend;

  Color get _backgroundColor => _friend.color != null ? hexToColor(_friend.color!) : Colors.grey;

  // Palette colors span light and dark, so pick readable text per-tile rather than a
  // single fixed color.
  Color get _textColor => _backgroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  String get _initials {
    final trimmed = _friend.username.trim();
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
                CircleAvatar(
                  key: Key('friendAvatar_${_friend.userId}'),
                  radius: 16,
                  backgroundImage: (_friend.profilePictureUrl != null && !_pictureFailedToLoad)
                      ? NetworkImage(_friend.profilePictureUrl!)
                      : null,
                  // CircleAvatar asserts backgroundImage != null || onBackgroundImageError == null,
                  // so this must be gated on the exact same condition as backgroundImage above -
                  // once _pictureFailedToLoad flips, both need to go null together.
                  onBackgroundImageError: (_friend.profilePictureUrl != null && !_pictureFailedToLoad)
                      ? (exception, stackTrace) {
                          if (mounted) setState(() => _pictureFailedToLoad = true);
                        }
                      : null,
                  child: (_friend.profilePictureUrl == null || _pictureFailedToLoad)
                      ? Text(_initials)
                      : null,
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
