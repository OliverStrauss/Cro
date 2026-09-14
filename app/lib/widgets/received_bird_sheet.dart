import 'package:flutter/material.dart';

import '../services/bird_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'bird_payload_view.dart';

// Dialog shown when tapping a bird someone else sent that's landed at the caller's own
// nest - for reading an arrived message: no ETA/progress, just who sent it and the payload
// itself (text, image, and/or a voice clip, whichever the bird's type carries). Marks the
// bird read on open - same as opening a text thread marks it read elsewhere. A centered
// Dialog (send_bird_dialog.dart's shell) rather than a bottom sheet - this is the web UI,
// which has no bottom-sheet convention elsewhere.
class ReceivedBirdSheet extends StatefulWidget {
  final String birdId;
  final String name;
  final String type;
  final String senderId;
  final String? content;
  final String? audioUrl;
  final String? imageUrl;
  final bool isRead;
  final String token;
  final ProfileService profileService;
  final BirdService birdService;

  const ReceivedBirdSheet({
    super.key,
    required this.birdId,
    required this.name,
    required this.type,
    required this.senderId,
    this.content,
    this.audioUrl,
    this.imageUrl,
    required this.isRead,
    required this.token,
    required this.profileService,
    required this.birdService,
  });

  static Future<void> show(
    BuildContext context, {
    required String birdId,
    required String name,
    required String type,
    required String senderId,
    String? content,
    String? audioUrl,
    String? imageUrl,
    required bool isRead,
    required String token,
    required ProfileService profileService,
    required BirdService birdService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ReceivedBirdSheet(
        birdId: birdId,
        name: name,
        type: type,
        senderId: senderId,
        content: content,
        audioUrl: audioUrl,
        imageUrl: imageUrl,
        isRead: isRead,
        token: token,
        profileService: profileService,
        birdService: birdService,
      ),
    );
  }

  @override
  State<ReceivedBirdSheet> createState() => _ReceivedBirdSheetState();
}

class _ReceivedBirdSheetState extends State<ReceivedBirdSheet> {
  String _senderLabel = '…';

  @override
  void initState() {
    super.initState();
    _loadSender();
    if (!widget.isRead) {
      _markRead();
    }
  }

  // Fire-and-forget - a failed read-receipt shouldn't block the caller from reading the
  // message they already have on screen.
  Future<void> _markRead() async {
    try {
      await widget.birdService.markBirdRead(widget.token, widget.birdId);
    } catch (_) {
      // See comment above - not worth surfacing.
    }
  }

  Future<void> _loadSender() async {
    try {
      final profile = await widget.profileService.getUser(widget.senderId);
      if (!mounted) return;
      setState(() => _senderLabel = profile.username);
    } catch (_) {
      if (!mounted) return;
      setState(() => _senderLabel = 'someone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('receivedBirdSheet'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: CroColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.type} · From $_senderLabel',
                  key: const Key('receivedBirdSender'),
                  style: CroTextStyles.data(size: 13),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BirdPayloadView(
                    content: widget.content,
                    audioUrl: widget.audioUrl,
                    imageUrl: widget.imageUrl,
                  ),
                ),
                const SizedBox(height: 18),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('receivedBirdCloseButton'),
                    borderRadius: CroBorders.radiusSmall,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text('Close', style: CroTextStyles.label(size: 12, color: CroColors.deepWaypoint)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
