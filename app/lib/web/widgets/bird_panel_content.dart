import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/bird_reaction.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../services/bird_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../widgets/bird_payload_view.dart';
import '../../widgets/send_bird_dialog.dart';
import 'dock_bird_card.dart';
import 'panel_header.dart';

// This app's thematic reaction set - distinct from the shared `availableReactionEmojis`
// (models/bird_reaction.dart), which the *phone* app's BirdDetailsSheet also uses and which
// this change doesn't touch.
const _webReactionEmojis = ['🕊️', '🌿', '⭐', '🔥'];

/// The bird detail panel body - adapted from the phone app's BirdDetailsSheet: where/when,
/// a progress bar, the payload (always visible - it's always the caller's own bird), a
/// reaction row for public birds, and a state-dependent footer action. Only the caller's
/// own birds are selectable in this pass
/// (see WebMapScreen/YourBirdsDock), so the sender is always "you" - a friend's bird would
/// need a different data shape (FriendBird, not Bird) this panel doesn't handle yet.
class BirdPanelContent extends StatefulWidget {
  final Bird bird;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final AuthState authState;
  final BirdReactionService reactionService;
  final BirdService birdService;
  final VoidCallback onClose;
  final VoidCallback onDataChanged;
  final VoidCallback onFollowOnMap;
  final VoidCallback onComposePressed;

  const BirdPanelContent({
    super.key,
    required this.bird,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
    required this.authState,
    required this.reactionService,
    required this.birdService,
    required this.onClose,
    required this.onDataChanged,
    required this.onFollowOnMap,
    required this.onComposePressed,
  });

  @override
  State<BirdPanelContent> createState() => _BirdPanelContentState();
}

class _BirdPanelContentState extends State<BirdPanelContent> {
  List<BirdReactionSummary> _reactions = [];
  bool _isLoadingReactions = false;

  @override
  void initState() {
    super.initState();
    if (widget.bird.isPublic) _loadReactions();
  }

  @override
  void didUpdateWidget(covariant BirdPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bird.id != widget.bird.id && widget.bird.isPublic) _loadReactions();
  }

  Future<void> _loadReactions() async {
    setState(() => _isLoadingReactions = true);
    try {
      final reactions = await widget.reactionService.getReactions(widget.authState.token!, widget.bird.id);
      if (!mounted) return;
      setState(() {
        _reactions = reactions;
        _isLoadingReactions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingReactions = false);
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    final existing = _reactionFor(emoji);
    try {
      List<BirdReactionSummary> updated;
      if (existing != null && existing.reactedByMe) {
        await widget.reactionService.removeReaction(widget.authState.token!, widget.bird.id, emoji);
        updated = await widget.reactionService.getReactions(widget.authState.token!, widget.bird.id);
      } else {
        updated = await widget.reactionService.addReaction(widget.authState.token!, widget.bird.id, emoji);
      }
      if (!mounted) return;
      setState(() => _reactions = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  BirdReactionSummary? _reactionFor(String emoji) {
    for (final r in _reactions) {
      if (r.emoji == emoji) return r;
    }
    return null;
  }

  String get _etaText {
    final eta = widget.bird.estimatedArrivalAt;
    if (eta == null) return 'In flight';
    final remaining = eta.difference(DateTime.now());
    if (remaining.isNegative) return 'Arriving any moment';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0 ? 'Arrives in ${hours}h ${minutes}m' : 'Arrives in ${minutes}m';
  }

  // Only ever called for flight/home - hub/away show neither the bar nor this note, since
  // the header chip already says where the bird landed.
  String _progressNote(DockBirdView view) => switch (view.state) {
    BirdDockState.flight => '${(view.progress * 100).round()}% of the way there',
    BirdDockState.home => 'Home and rested',
    _ => '',
  };

  Future<void> _callItHome() async {
    final destinations = widget.ownNests
        .where((n) => n.id != widget.bird.currentNestId)
        .map((n) => SendBirdDestination(nestId: n.id, label: n.name))
        .toList();
    final result = await showDialog<SendBirdResult>(
      context: context,
      builder: (_) => SendBirdDialog(destinations: destinations),
    );
    if (result == null || !mounted) return;

    try {
      await widget.birdService.sendBird(widget.authState.token!, widget.bird.id, nestId: result.nestId, content: result.content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.bird.name} is on its way home')));
      widget.onDataChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  // Relays the bird from wherever it's currently parked (a hub or a friend's nest) onward
  // to a different friend's nest (or back to one of the sender's own), each hop carrying
  // its own message - mirrors NestPanelContent._openSendFlow's destination list, just built
  // from the lists already passed into this panel instead of re-fetched.
  Future<void> _sendOnward() async {
    final bird = widget.bird;
    final destinations = [
      ...widget.ownNests
          .where((n) => n.id != bird.currentNestId)
          .map((n) => SendBirdDestination(nestId: n.id, label: n.name)),
      ...widget.friendWaypoints
          .where((n) => n.id != bird.currentNestId)
          .map((n) => SendBirdDestination(nestId: n.id, label: '${n.name} (${n.username})')),
    ];
    final result = await showDialog<SendBirdResult>(
      context: context,
      builder: (_) => SendBirdDialog(destinations: destinations),
    );
    if (result == null || !mounted) return;

    try {
      await widget.birdService.sendBird(widget.authState.token!, bird.id, nestId: result.nestId, content: result.content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${bird.name} is on its way')));
      widget.onDataChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bird = widget.bird;
    final view = DockBirdView.resolve(
      bird: bird,
      ownNests: widget.ownNests,
      friendWaypoints: widget.friendWaypoints,
      hubs: widget.hubs,
    );
    // This panel only ever shows the caller's own bird (see the class doc comment) and
    // GET /birds never withholds Content/AudioUrl/ImageUrl the way GET /friends/birds does
    // for someone else's - IsPublic only ever gates whether *other* people can see it
    // (reactions, a friend's/Hub view), never the sender's own read of their own message.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(
          avatar: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_forward_rounded, size: 22, color: Colors.white),
          ),
          title: bird.name,
          subtitle: '${bird.type} · ${BirdType.description(bird.type)} · sent by you',
          chip: view == null
              ? null
              : Container(
                  key: const Key('birdPanelStateChip'),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: view.stateColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    view.stateLabel,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: view.stateColor),
                  ),
                ),
          onClose: widget.onClose,
        ),
        Flexible(
          child: view == null
              ? const Center(
                  key: Key('birdPanelUnplaceable'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "This bird's current location can't be found right now.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: CroColors.fog),
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  children: [
                    _labelValueRow(bird.isTraveling ? 'Flying to' : 'Resting at', view.hostName),
                    const SizedBox(height: 8),
                    _labelValueRow('Arrival', bird.isTraveling ? _etaText : 'Sitting there'),
                    const SizedBox(height: 12),
                    // The bird's already arrived at this state - no bar (away) and no note
                    // under it (hub/away), since the header chip already says where it is.
                    if (view.state != BirdDockState.away) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: view.progress,
                          minHeight: 6,
                          backgroundColor: CroColors.ink.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (view.state == BirdDockState.flight || view.state == BirdDockState.home)
                      Text(
                        _progressNote(view),
                        key: const Key('birdPanelProgressNote'),
                        style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: CroColors.altSurface, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What it carries',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          BirdPayloadView(
                            content: bird.content,
                            imageUrl: bird.imageUrl,
                            audioUrl: bird.type == BirdType.parrot ? null : bird.audioUrl,
                          ),
                          if (bird.type == BirdType.parrot && bird.audioUrl != null)
                            _ParrotWaveform(audioUrl: bird.audioUrl!, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                    if (bird.isPublic) ...[
                      const SizedBox(height: 18),
                      const Text('Reactions', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 9),
                      Wrap(
                        key: const Key('webBirdReactionRow'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final emoji in _webReactionEmojis) _reactionChip(emoji)],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _footerButton(view),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _footerButton(DockBirdView view) => switch (view.state) {
    BirdDockState.flight => _actionButton(
      keyName: 'birdPanelFollowOnMap',
      label: 'Follow on the map',
      bg: CroColors.warmSurface,
      fg: CroColors.deepWaypoint,
      onTap: widget.onFollowOnMap,
    ),
    BirdDockState.home => _actionButton(
      keyName: 'birdPanelSendSomewhere',
      label: 'Send this bird somewhere',
      bg: CroColors.waypointBlue,
      fg: Colors.white,
      onTap: widget.onComposePressed,
    ),
    BirdDockState.away || BirdDockState.hub => Column(
      children: [
        _actionButton(
          keyName: 'birdPanelSendOnward',
          label: 'Send onward',
          bg: CroColors.waypointBlue,
          fg: Colors.white,
          onTap: _sendOnward,
        ),
        const SizedBox(height: 8),
        _actionButton(
          keyName: 'birdPanelCallItHome',
          label: 'Call it home',
          bg: CroColors.warmSurface,
          fg: CroColors.deepWaypoint,
          onTap: _callItHome,
        ),
      ],
    ),
  };

  Widget _actionButton({
    required String keyName,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: Key(keyName),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }

  Widget _labelValueRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: CroColors.fog)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _reactionChip(String emoji) {
    final summary = _reactionFor(emoji);
    final count = summary?.count ?? 0;
    final mine = summary?.reactedByMe ?? false;
    return GestureDetector(
      key: Key('webReactionChip_$emoji'),
      onTap: _isLoadingReactions ? null : () => _toggleReaction(emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: mine ? CroColors.waypointBlue.withValues(alpha: 0.16) : CroColors.altSurface,
          border: Border.all(color: mine ? CroColors.waypointBlue.withValues(alpha: 0.5) : CroColors.ink.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text('$count', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: mine ? CroColors.deepWaypoint : CroColors.fog)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A Parrot payload's audio row: a play button plus a 24-bar waveform. The bars are a fixed
/// decorative pattern (not real audio analysis - the backend doesn't provide amplitude
/// data), matching the design reference's own formula exactly so it isn't just a generic
/// player. The duration starts as a placeholder and fills in once the player reports one.
class _ParrotWaveform extends StatefulWidget {
  final String audioUrl;
  final Color color;

  const _ParrotWaveform({required this.audioUrl, required this.color});

  @override
  State<_ParrotWaveform> createState() => _ParrotWaveformState();
}

class _ParrotWaveformState extends State<_ParrotWaveform> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.audioUrl));
    }
    if (!mounted) return;
    setState(() => _isPlaying = !_isPlaying);
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
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Row(
        children: [
          GestureDetector(
            key: const Key('birdPanelWaveformPlay'),
            onTap: _toggle,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 18, color: Colors.white),
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
          Text(_durationText, style: const TextStyle(fontSize: 11, color: CroColors.fog)),
        ],
      ),
    );
  }
}
