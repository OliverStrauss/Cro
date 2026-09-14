import 'package:flutter/material.dart';

import '../../models/pinned_bird.dart';
import '../../services/friends_service.dart';
import '../../theme.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../../widgets/bird_payload_view.dart';

// One card in a Pinned view (see web_pinned_screen.dart) - same chrome as HubMessageCard,
// since the pinned view is deliberately styled like a Hub's message board. onRemove is
// supplied by the caller rather than decided here: on the "Yours" tab it's always the
// receiver unpinning their own saved message; on the "Public" tab it's only present when the
// viewer is the original sender taking their own pin down (see PinService.UnpinAsync for the
// server-side rule this mirrors).
class PinnedMessageCard extends StatefulWidget {
  final PinnedBird pin;
  final bool showAddFriend;
  final String token;
  final FriendsService friendsService;
  final String? removeTooltip;
  final Future<void> Function()? onRemove;

  const PinnedMessageCard({
    super.key,
    required this.pin,
    required this.showAddFriend,
    required this.token,
    required this.friendsService,
    this.removeTooltip,
    this.onRemove,
  });

  @override
  State<PinnedMessageCard> createState() => _PinnedMessageCardState();
}

class _PinnedMessageCardState extends State<PinnedMessageCard> {
  bool _isSendingFriendRequest = false;
  bool _friendRequestSent = false;
  bool _isRemoving = false;

  String get _relativeTime {
    final elapsed = DateTime.now().difference(widget.pin.createdAt);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  Future<void> _addFriend() async {
    setState(() => _isSendingFriendRequest = true);
    try {
      await widget.friendsService.sendFriendRequest(widget.token, widget.pin.senderUsername);
      if (!mounted) return;
      setState(() => _friendRequestSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${widget.pin.senderUsername}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _isSendingFriendRequest = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _isRemoving = true);
    try {
      await widget.onRemove!();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _isRemoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return Card(
      key: Key('pinnedMessageCard_${pin.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AvatarWithFallback(
                  avatarKey: Key('pinnedMessageAvatar_${pin.id}'),
                  imageUrl: null,
                  initialsSource: pin.senderUsername,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.senderUsername,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CroColors.ink),
                      ),
                      Text(
                        '${pin.birdName} · from ${pin.originNestName ?? 'somewhere'} · $_relativeTime',
                        key: Key('pinnedMessageMeta_${pin.id}'),
                        style: CroTextStyles.data(size: 12),
                      ),
                    ],
                  ),
                ),
                if (widget.showAddFriend)
                  IconButton(
                    key: Key('pinnedMessageAddFriendButton_${pin.id}'),
                    tooltip: 'Add friend',
                    icon: Icon(
                      _friendRequestSent ? Icons.check_circle : Icons.person_add_alt_1,
                      color: _friendRequestSent ? Theme.of(context).colorScheme.primary : null,
                    ),
                    onPressed: _isSendingFriendRequest || _friendRequestSent ? null : _addFriend,
                  ),
                if (widget.onRemove != null)
                  IconButton(
                    key: Key('pinnedMessageRemoveButton_${pin.id}'),
                    tooltip: widget.removeTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: _isRemoving ? null : _remove,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            BirdPayloadView(
              content: pin.content,
              audioUrl: pin.audioUrl,
              imageUrl: pin.imageUrl,
            ),
          ],
        ),
      ),
    );
  }
}
