import 'package:flutter/material.dart';

import '../../models/public_bird.dart';
import '../../services/friends_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../../widgets/bird_payload_view.dart';
import 'panel_header.dart';

/// Read-only detail view for a stranger's public bird - opened by tapping a public bird
/// marker on the map (see WebMapScreen). A sibling to FriendBirdPanelContent rather than an
/// extension of it: PublicBird carries no nest ids or timestamps (see its own doc comment),
/// so there's no "where/when"/progress row to build, and reactions stay friend-gated (out of
/// scope for a stranger). What this adds instead is the one thing the friend panel never
/// needs: an Add Friend action, since the point of this view is introducing the caller to
/// someone they aren't friends with yet.
class PublicBirdPanelContent extends StatefulWidget {
  final PublicBird bird;
  final AuthState authState;
  final FriendsService friendsService;
  final VoidCallback onClose;

  const PublicBirdPanelContent({
    super.key,
    required this.bird,
    required this.authState,
    required this.friendsService,
    required this.onClose,
  });

  @override
  State<PublicBirdPanelContent> createState() => _PublicBirdPanelContentState();
}

class _PublicBirdPanelContentState extends State<PublicBirdPanelContent> {
  bool _isSending = false;
  bool _sent = false;

  Future<void> _sendRequest() async {
    setState(() => _isSending = true);
    try {
      await widget.friendsService.sendFriendRequest(widget.authState.token!, widget.bird.senderUsername);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bird = widget.bird;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(
          avatar: AvatarWithFallback(
            imageUrl: bird.senderProfilePictureUrl,
            initialsSource: bird.senderUsername,
            radius: 25,
          ),
          title: bird.senderUsername,
          subtitle: '${bird.type} · sent this publicly',
          onClose: widget.onClose,
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            children: [
              if (BirdPayloadView.hasPayload(content: bird.content, audioUrl: bird.audioUrl, imageUrl: bird.imageUrl)) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: CroColors.altSurface, borderRadius: CroBorders.radius, border: Border.all(color: CroColors.hairline)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WHAT IT CARRIES', style: CroTextStyles.label(size: 11.5)),
                      const SizedBox(height: 8),
                      BirdPayloadView(content: bird.content, imageUrl: bird.imageUrl, audioUrl: bird.audioUrl),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Material(
                color: _sent ? CroColors.altSurface : CroColors.warmSurface,
                borderRadius: CroBorders.radius,
                child: InkWell(
                  key: const Key('publicBirdPanelAddFriend'),
                  borderRadius: CroBorders.radius,
                  onTap: _isSending || _sent ? null : _sendRequest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        (_sent ? 'Request sent' : 'Add ${bird.senderUsername} as a friend').toUpperCase(),
                        style: CroTextStyles.label(size: 12, color: CroColors.deepWaypoint),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
