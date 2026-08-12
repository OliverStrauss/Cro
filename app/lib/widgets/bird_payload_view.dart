import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// A bird's text/image/audio message, whichever of the three it carries - shared by
// ReceivedBirdSheet (a privately delivered bird, always readable) and BirdDetailsSheet (an
// in-flight bird, readable early only when it's public). Owns its own AudioPlayer so callers
// don't need to manage play/pause state or the player's lifecycle themselves.
class BirdPayloadView extends StatefulWidget {
  final String? content;
  final String? audioUrl;
  final String? imageUrl;

  const BirdPayloadView({super.key, this.content, this.audioUrl, this.imageUrl});

  @override
  State<BirdPayloadView> createState() => _BirdPayloadViewState();
}

class _BirdPayloadViewState extends State<BirdPayloadView> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    });
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
    final hasContent = widget.content != null && widget.content!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContent)
          Text(
            widget.content!,
            key: const Key('birdPayloadContent'),
            style: const TextStyle(fontSize: 14, color: CroColors.ink),
          ),
        if (widget.imageUrl != null) ...[
          if (hasContent) const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(widget.imageUrl!, key: const Key('birdPayloadImage')),
          ),
        ],
        if (widget.audioUrl != null) ...[
          if (hasContent || widget.imageUrl != null) const SizedBox(height: 12),
          GestureDetector(
            key: const Key('birdPayloadAudioButton'),
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
