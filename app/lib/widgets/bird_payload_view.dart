import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// A bird's text/image/audio message, whichever of the three it carries - shared by every
// place a bird's payload is shown: the dock's own-bird panel, a friend's or public bird
// panel, a Hub message card, a pinned message card, and ReceivedBirdSheet/BirdDetailsSheet.
// Owns its own AudioPlayer so callers don't need to manage play/pause state or the player's
// lifecycle themselves. [audioUrl] is Parrot-exclusive (backend validation never sets it for
// any other bird type), so its waveform row doesn't need a separate bird-type check.
class BirdPayloadView extends StatefulWidget {
  final String? content;
  final String? audioUrl;
  final String? imageUrl;

  const BirdPayloadView({super.key, this.content, this.audioUrl, this.imageUrl});

  // Whether there's anything here to show at all - callers that wrap this in their own
  // "What it carries" heading use it to hide that heading entirely instead of showing it
  // over an empty/placeholder body.
  static bool hasPayload({String? content, String? audioUrl, String? imageUrl}) =>
      (content != null && content.isNotEmpty) || audioUrl != null || imageUrl != null;

  @override
  State<BirdPayloadView> createState() => _BirdPayloadViewState();
}

class _BirdPayloadViewState extends State<BirdPayloadView> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
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

  String get _durationText {
    final d = _duration;
    if (d == null) return '--:--';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
          // A fixed decorative bar pattern (not real audio analysis - the backend doesn't
          // provide amplitude data), matching the design reference's own formula exactly so
          // it isn't just a generic player. The duration starts as a placeholder and fills
          // in once the player reports one.
          Row(
            key: const Key('birdPayloadWaveform'),
            children: [
              Tooltip(
                message: _isPlayingAudio ? 'Pause' : 'Play',
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('birdPayloadAudioButton'),
                    customBorder: const CircleBorder(),
                    onTap: _toggleAudio,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: Icon(
                          _isPlayingAudio ? Icons.pause : Icons.play_arrow,
                          size: 18,
                          color: CroColors.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 24; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          child: FractionallySizedBox(
                            heightFactor: (30 + (i * 37) % 70) / 100,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: CroColors.deepWaypoint.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text(_durationText, style: CroTextStyles.data(size: 11)),
            ],
          ),
        ],
        if (!hasContent && widget.imageUrl == null && widget.audioUrl == null)
          const Text('This bird carried no message.', style: TextStyle(fontSize: 13, color: CroColors.fog)),
      ],
    );
  }
}
