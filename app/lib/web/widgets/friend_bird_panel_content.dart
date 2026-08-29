import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/bird_reaction.dart';
import '../../models/friend_bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../widgets/bird_payload_view.dart';
import 'panel_header.dart';

// Public-only reaction set, matching bird_panel_content.dart's web-scoped emoji list.
const _webReactionEmojis = ['🕊️', '🌿', '⭐', '🔥'];

/// Read-only detail view for a friend's public bird - opened by tapping a public friend bird
/// marker on the map (see WebMapScreen). Deliberately much thinner than BirdPanelContent:
/// FriendBird only ever models a still-in-flight bird (see friend_bird.dart), so there's no
/// state chip, progress-note table, or resting-state footer action to build - just where/when,
/// the payload (always present, since a friend bird is only ever exposed here when public),
/// reactions, and a single "Follow on the map" action. Nothing here can mutate the bird
/// itself (no send/recall) since it isn't the caller's.
class FriendBirdPanelContent extends StatefulWidget {
  final FriendBird bird;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final AuthState authState;
  final BirdReactionService reactionService;
  final VoidCallback onClose;
  final VoidCallback onFollowOnMap;

  const FriendBirdPanelContent({
    super.key,
    required this.bird,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
    required this.authState,
    required this.reactionService,
    required this.onClose,
    required this.onFollowOnMap,
  });

  @override
  State<FriendBirdPanelContent> createState() => _FriendBirdPanelContentState();
}

class _FriendBirdPanelContentState extends State<FriendBirdPanelContent> {
  List<BirdReactionSummary> _reactions = [];
  bool _isLoadingReactions = false;

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  @override
  void didUpdateWidget(covariant FriendBirdPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bird.id != widget.bird.id) _loadReactions();
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

  String _nameFor(String? id) {
    if (id == null) return 'somewhere';
    for (final n in [...widget.ownNests, ...widget.friendWaypoints]) {
      if (n.id == id) return n.name;
    }
    for (final h in widget.hubs) {
      if (h.id == id) return h.name;
    }
    return 'somewhere';
  }

  String get _etaText {
    final remaining = widget.bird.estimatedArrivalAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Arriving any moment';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0 ? 'Arrives in ${hours}h ${minutes}m' : 'Arrives in ${minutes}m';
  }

  double get _progress {
    final total = widget.bird.estimatedArrivalAt.difference(widget.bird.departedAt);
    if (total <= Duration.zero) return 1;
    return (DateTime.now().difference(widget.bird.departedAt).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final bird = widget.bird;
    final color = bird.color != null ? hexToColor(bird.color!) : CroColors.fog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          avatar: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_forward_rounded, size: 22, color: Colors.white),
          ),
          title: bird.name,
          subtitle: '${bird.type} · ${BirdType.description(bird.type)} · sent by ${bird.username}',
          onClose: widget.onClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            children: [
              _labelValueRow('Flying to', _nameFor(bird.nestToId)),
              const SizedBox(height: 8),
              _labelValueRow('Arrival', _etaText),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: CroColors.ink.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).round()}% of the way there',
                style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: CroColors.altSurface, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('What it carries', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    BirdPayloadView(content: bird.content, imageUrl: bird.imageUrl, audioUrl: bird.audioUrl),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('Reactions', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 9),
              Wrap(
                key: const Key('webFriendBirdReactionRow'),
                spacing: 8,
                runSpacing: 8,
                children: [for (final emoji in _webReactionEmojis) _reactionChip(emoji)],
              ),
              const SizedBox(height: 18),
              GestureDetector(
                key: const Key('friendBirdPanelFollowOnMap'),
                onTap: widget.onFollowOnMap,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: CroColors.warmSurface, borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    'Follow on the map',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                  ),
                ),
              ),
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
      key: Key('webFriendReactionChip_$emoji'),
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
