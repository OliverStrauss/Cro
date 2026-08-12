import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/bird_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';

// Bottom sheet shown when tapping a bird someone else sent that's landed at the caller's
// own nest - same chrome as BirdDetailsSheet, but for reading an arrived message instead of
// tracking one still in flight: no ETA/progress, just who sent it and the payload itself
// (text, image, and/or a voice clip, whichever the bird's type carries). Marks the bird read
// on open - same as opening a text thread marks it read elsewhere.
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _loadSender();
    if (!widget.isRead) {
      _markRead();
    }
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    });
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

  Future<void> _toggleAudio() async {
    if (_isPlayingAudio) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.audioUrl!));
    }
    if (!mounted) return;
    setState(() => _isPlayingAudio = !_isPlayingAudio);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('receivedBirdSheet'),
      decoration: const BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        // rgba(43,47,51,0.18) per the sheet-shadow token.
        boxShadow: [BoxShadow(color: Color(0x2E2B2F33), blurRadius: 30, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  // rgba(43,47,51,0.15) drag-handle token.
                  color: const Color(0x262B2F33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
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
                          style: const TextStyle(fontSize: 13, color: CroColors.fog),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: _buildPayload()),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayload() {
    final hasContent = widget.content != null && widget.content!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContent)
          Text(
            widget.content!,
            key: const Key('receivedBirdContent'),
            style: const TextStyle(fontSize: 14, color: CroColors.ink),
          ),
        if (widget.imageUrl != null) ...[
          if (hasContent) const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(widget.imageUrl!, key: const Key('receivedBirdImage')),
          ),
        ],
        if (widget.audioUrl != null) ...[
          if (hasContent || widget.imageUrl != null) const SizedBox(height: 12),
          GestureDetector(
            key: const Key('receivedBirdAudioButton'),
            onTap: _toggleAudio,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isPlayingAudio ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Voice message', style: TextStyle(fontSize: 13, color: CroColors.ink)),
              ],
            ),
          ),
        ],
        if (!hasContent && widget.imageUrl == null && widget.audioUrl == null)
          const Text('This bird carried no message.', style: TextStyle(fontSize: 13, color: CroColors.fog)),
      ],
    );
  }
}
