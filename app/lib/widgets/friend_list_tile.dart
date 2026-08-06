import 'package:flutter/material.dart';

import '../models/friend.dart';

// Purely presentational: leading avatar + username. Kept free of any trailing
// content so a future color-swatch addition can extend this without restructuring
// the callers that compose it (e.g. friends_screen.dart's remove button sits
// alongside this widget, not inside it).
class FriendListTile extends StatelessWidget {
  final Friend friend;

  const FriendListTile({super.key, required this.friend});

  String get _initials {
    final trimmed = friend.username.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('friendTile_${friend.userId}'),
      leading: CircleAvatar(child: Text(_initials)),
      title: Text(friend.username),
    );
  }
}
