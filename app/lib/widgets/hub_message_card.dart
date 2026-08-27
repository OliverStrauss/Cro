import 'package:flutter/material.dart';

import '../models/hub_message.dart';
import '../services/friends_service.dart';
import '../theme.dart';
import 'avatar_with_fallback.dart';
import 'bird_payload_view.dart';

// One card on a Hub's message board. showAddFriend is decided by the caller (self,
// already-friend, and already-pending senders are excluded) rather than by this widget,
// since that requires the viewer's own id plus their friends/requests lists.
class HubMessageCard extends StatefulWidget {
  final HubMessage message;
  final bool showAddFriend;
  final String token;
  final FriendsService friendsService;

  const HubMessageCard({
    super.key,
    required this.message,
    required this.showAddFriend,
    required this.token,
    required this.friendsService,
  });

  @override
  State<HubMessageCard> createState() => _HubMessageCardState();
}

class _HubMessageCardState extends State<HubMessageCard> {
  bool _isSending = false;
  bool _sent = false;

  String get _relativeTime {
    final elapsed = DateTime.now().difference(widget.message.createdAt);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  Future<void> _addFriend() async {
    setState(() => _isSending = true);
    try {
      await widget.friendsService.sendFriendRequest(widget.token, widget.message.senderUsername);
      if (!mounted) return;
      setState(() => _sent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${widget.message.senderUsername}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return Card(
      key: Key('hubMessageCard_${message.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AvatarWithFallback(
                  avatarKey: Key('hubMessageAvatar_${message.id}'),
                  imageUrl: message.senderProfilePictureUrl,
                  initialsSource: message.senderUsername,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.senderUsername,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CroColors.ink),
                      ),
                      Text(
                        '${message.birdName} · from ${message.originNestName ?? 'somewhere'} · $_relativeTime',
                        key: Key('hubMessageMeta_${message.id}'),
                        style: const TextStyle(fontSize: 12, color: CroColors.fog),
                      ),
                    ],
                  ),
                ),
                if (widget.showAddFriend)
                  IconButton(
                    key: Key('hubMessageAddFriendButton_${message.id}'),
                    tooltip: 'Add friend',
                    icon: Icon(
                      _sent ? Icons.check_circle : Icons.person_add_alt_1,
                      color: _sent ? Theme.of(context).colorScheme.primary : null,
                    ),
                    onPressed: _isSending || _sent ? null : _addFriend,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            BirdPayloadView(
              content: message.content,
              audioUrl: message.audioUrl,
              imageUrl: message.imageUrl,
            ),
          ],
        ),
      ),
    );
  }
}
