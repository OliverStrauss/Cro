import 'package:flutter/material.dart';

import 'avatar_with_fallback.dart';

// Sibling of FriendListTile - same fixed-width vertical card shape, but for a pending
// friend request (accept/decline instead of a color picker).
class InviteCard extends StatelessWidget {
  final String userId;
  final String username;
  final String? profilePictureUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const InviteCard({
    super.key,
    required this.userId,
    required this.username,
    required this.profilePictureUrl,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('inviteCard_$userId'),
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(
            avatarKey: Key('inviteAvatar_$userId'),
            imageUrl: profilePictureUrl,
            initialsSource: username,
            radius: 24,
          ),
          const SizedBox(height: 8),
          Text(username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                key: Key('acceptRequestButton_$userId'),
                onTap: onAccept,
                child: Icon(Icons.check, size: 18, color: Colors.green.shade700),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                key: Key('declineRequestButton_$userId'),
                onTap: onDecline,
                child: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
