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
            child: Image.network(
              widget.imageUrl!,
              key: const Key('birdPayloadImage'),
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => Container(
                width: double.infinity,
                height: 200,
                color: CroColors.fog.withValues(alpha: 0.15),
                alignment: Alignment.center,
                child: const Icon(Icons.image_not_supported_outlined, color: CroColors.fog),
              ),
            ),
          ),
        ],
        if (widget.audioUrl != null) ...[
          if (hasContent || widget.imageUrl != null) const SizedBox(height: 12),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('birdPayloadAudioButton'),
              borderRadius: BorderRadius.circular(8),
              onTap: _toggleAudio,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
            ),
          ),
        ],
        if (!hasContent && widget.imageUrl == null && widget.audioUrl == null)
          const Text('This bird carried no message.', style: TextStyle(fontSize: 13, color: CroColors.fog)),
      ],
    );
  }
}
