import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/bird_reaction.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../widgets/bird_payload_view.dart';
import 'panel_header.dart';

/// The bird detail panel body - adapted from the phone app's BirdDetailsSheet: where/when,
/// a progress bar, the payload (sealed if private), and a reaction row for public birds.
/// Only the caller's own birds are selectable in this pass (see WebMapScreen/YourBirdsDock),
/// so the sender is always "you" - a friend's bird would need a different data shape
/// (FriendBird, not Bird) this panel doesn't handle yet.
class BirdPanelContent extends StatefulWidget {
  final Bird bird;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final AuthState authState;
  final BirdReactionService reactionService;
  final VoidCallback onClose;

  const BirdPanelContent({
    super.key,
    required this.bird,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
    required this.authState,
    required this.reactionService,
    required this.onClose,
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

  String? _nameFor(String? id) {
    if (id == null) return null;
    for (final n in widget.ownNests) {
      if (n.id == id) return n.name;
    }
    for (final n in widget.friendWaypoints) {
      if (n.id == id) return n.name;
    }
    for (final h in widget.hubs) {
      if (h.id == id) return h.name;
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

  double get _progressFraction {
    final departed = widget.bird.departedAt;
    final eta = widget.bird.estimatedArrivalAt;
    if (departed == null || eta == null) return 1;
    final total = eta.difference(departed);
    if (total <= Duration.zero) return 1;
    return (DateTime.now().difference(departed).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final bird = widget.bird;
    final targetId = bird.isTraveling ? bird.nestToId : bird.currentNestId;
    final targetName = _nameFor(targetId) ?? 'somewhere';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          avatar: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_drop_up, size: 26, color: Colors.white),
          ),
          title: bird.name,
          subtitle: '${bird.type} · sent by you',
          onClose: widget.onClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            children: [
              _labelValueRow(bird.isTraveling ? 'Flying to' : 'Resting at', targetName),
              const SizedBox(height: 8),
              _labelValueRow('Arrival', bird.isTraveling ? _etaText : 'Sitting there'),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progressFraction,
                  minHeight: 6,
                  backgroundColor: CroColors.ink.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: CroColors.altSurface, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bird.isPublic ? 'What it carries' : 'Sealed until it lands',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (bird.isPublic)
                      BirdPayloadView(content: bird.content, audioUrl: bird.audioUrl, imageUrl: bird.imageUrl)
                    else
                      const Text(
                        'This bird is private. The message stays sealed until it reaches its nest.',
                        style: TextStyle(fontSize: 12.5, color: CroColors.fog),
                      ),
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
                  children: [for (final emoji in availableReactionEmojis) _reactionChip(emoji)],
                ),
              ],
            ],
          ),
        ),
      ],
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
