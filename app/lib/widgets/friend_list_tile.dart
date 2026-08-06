import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../utils/color_utils.dart';

class FriendListTile extends StatelessWidget {
  final Friend friend;
  final ValueChanged<String>? onColorSelected;

  const FriendListTile({super.key, required this.friend, this.onColorSelected});

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
    return ListTile(
      key: Key('friendTile_${friend.userId}'),
      leading: CircleAvatar(child: Text(_initials)),
      title: Text(friend.username),
      trailing: onColorSelected == null
          ? null
          : GestureDetector(
              key: Key('colorSwatch_${friend.userId}'),
              onTap: () => _pickColor(context),
              child: CircleAvatar(
                backgroundColor: friend.color != null ? hexToColor(friend.color!) : Colors.grey,
                radius: 14,
              ),
            ),
    );
  }
}
