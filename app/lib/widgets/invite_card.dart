import 'package:flutter/material.dart';

import '../theme.dart';
import 'avatar_with_fallback.dart';

// Sibling of FriendListTile - same fixed-width vertical card shape, but for a pending
// friend request (accept/decline instead of a color picker).
class InviteCard extends StatelessWidget {
  final String userId;
  final String username;
  final String? profilePictureUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onBlock;

  const InviteCard({
    super.key,
    required this.userId,
    required this.username,
    required this.profilePictureUrl,
    required this.onAccept,
    required this.onDecline,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('inviteCard_$userId'),
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(
            avatarKey: Key('inviteAvatar_$userId'),
            imageUrl: profilePictureUrl,
            initialsSource: username,
            radius: 22,
          ),
          const SizedBox(height: 8),
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CroColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                key: Key('acceptRequestButton_$userId'),
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CroColors.waypointBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: CroColors.surface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                key: Key('declineRequestButton_$userId'),
                onTap: onDecline,
                child: const Text(
                  '×',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: CroColors.fog,
                  ),
                ),
              ),
            ],
          ),
          if (onBlock != null) ...[
            const SizedBox(height: 3),
            GestureDetector(
              key: Key('blockRequestButton_$userId'),
              onTap: onBlock,
              child: const Text(
                'Block',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: CroColors.fog,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
