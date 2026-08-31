import 'package:flutter/material.dart';

import '../models/bird_reaction.dart';
import '../services/bird_reaction_service.dart';
import '../theme.dart';
import 'bird_payload_view.dart';

// Bottom sheet shown when tapping a moving bird marker on the map - same chrome as
// NestDetailsSheet, mostly informational (who sent the bird, where it's headed, how far
// along its journey it is), plus a reaction row when the bird is public. Stateful only
// because of that reaction row - every other field is a snapshot of already-resolved data
// (MapScreen's _TravelingBird) rather than something this sheet fetches itself.
class BirdDetailsSheet extends StatefulWidget {
  final String birdId;
  final String name;
  final String type;
  // "You" for the caller's own bird, the friend's username for a friend's.
  final String senderLabel;
  final Color color;
  final String destinationName;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;
  final bool isPublic;
  final String token;
  // GET /birds (the caller's own) never withholds these regardless of isPublic - the sender
  // can always read their own message. Only GET /friends/birds withholds them for a friend's
  // still-private bird, so null here means "actually withheld" only for a friend's; see
  // showPayload in build().
  final String? content;
  final String? audioUrl;
  final String? imageUrl;
  final BirdReactionService? reactionService;

  const BirdDetailsSheet({
    super.key,
    required this.birdId,
    required this.name,
    required this.type,
    required this.senderLabel,
    required this.color,
    required this.destinationName,
    required this.departedAt,
    required this.estimatedArrivalAt,
    required this.isPublic,
    required this.token,
    this.content,
    this.audioUrl,
    this.imageUrl,
    this.reactionService,
  });

  static Future<void> show(
    BuildContext context, {
    required String birdId,
    required String name,
    required String type,
    required String senderLabel,
    required Color color,
    required String destinationName,
    required DateTime departedAt,
    required DateTime estimatedArrivalAt,
    required bool isPublic,
    required String token,
    String? content,
    String? audioUrl,
    String? imageUrl,
    BirdReactionService? reactionService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BirdDetailsSheet(
        birdId: birdId,
        name: name,
        type: type,
        senderLabel: senderLabel,
        color: color,
        destinationName: destinationName,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
        isPublic: isPublic,
        token: token,
        content: content,
        audioUrl: audioUrl,
        imageUrl: imageUrl,
        reactionService: reactionService,
      ),
    );
  }

  @override
  State<BirdDetailsSheet> createState() => _BirdDetailsSheetState();
}

class _BirdDetailsSheetState extends State<BirdDetailsSheet> {
  late final BirdReactionService _reactionService = widget.reactionService ?? BirdReactionService();
  List<BirdReactionSummary> _reactions = [];
  bool _isLoadingReactions = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPublic) {
      _loadReactions();
    }
  }

  Future<void> _loadReactions() async {
    setState(() => _isLoadingReactions = true);
    try {
      final reactions = await _reactionService.getReactions(widget.token, widget.birdId);
      if (!mounted) return;
      setState(() {
        _reactions = reactions;
        _isLoadingReactions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingReactions = false);
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    final existing = _reactionFor(emoji);
    try {
      List<BirdReactionSummary> updated;
      if (existing != null && existing.reactedByMe) {
        await _reactionService.removeReaction(widget.token, widget.birdId, emoji);
        updated = await _reactionService.getReactions(widget.token, widget.birdId);
      } else {
        updated = await _reactionService.addReaction(widget.token, widget.birdId, emoji);
      }
      if (!mounted) return;
      setState(() => _reactions = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  BirdReactionSummary? _reactionFor(String emoji) {
    for (final reaction in _reactions) {
      if (reaction.emoji == emoji) return reaction;
    }
    return null;
  }

  // Same relative-countdown shape as BirdsScreen._etaText - no `intl` dependency in this
  // project, so a plain "arrives in Xh Ym" rather than a formatted timestamp.
  String get _etaText {
    final remaining = widget.estimatedArrivalAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Arriving any moment';
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0
        ? 'Arrives in ${hours}h ${minutes}m'
        : 'Arrives in ${minutes}m';
  }

  double get _progressFraction {
    final totalDuration = widget.estimatedArrivalAt.difference(widget.departedAt);
    if (totalDuration <= Duration.zero) {
      return 1.0;
    }
    final fraction =
        DateTime.now().difference(widget.departedAt).inMilliseconds /
        totalDuration.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // The caller's own bird always carries its real content/audioUrl/imageUrl here (GET
    // /birds never withholds these) regardless of isPublic - only a *friend's* still-private
    // bird actually has them nulled out server-side (GET /friends/birds). So presence of any
    // payload field is itself the right signal for whether there's anything to show, not
    // isPublic alone - that only still gates the separate reaction row below.
    final showPayload = widget.isPublic || widget.content != null || widget.audioUrl != null || widget.imageUrl != null;
    return Container(
      key: const Key('birdDetailsSheet'),
      decoration: const BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        // rgba(43,47,51,0.18) per the sheet-shadow token.
        boxShadow: [
          BoxShadow(
            color: Color(0x2E2B2F33),
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      child: SafeArea(
        top: false,
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_drop_up,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: CroColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.type} · Sent by ${widget.senderLabel}',
                        key: const Key('birdDetailsSender'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: CroColors.fog,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _buildLabelValueRow(
              'Heading to',
              widget.destinationName,
              key: const Key('birdDetailsDestination'),
            ),
            const SizedBox(height: 8),
            _buildLabelValueRow(
              'ETA',
              _etaText,
              key: const Key('birdDetailsEta'),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                key: const Key('birdDetailsProgress'),
                value: _progressFraction,
                minHeight: 6,
                backgroundColor: CroColors.background,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
            if (showPayload) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: BirdPayloadView(
                  content: widget.content,
                  audioUrl: widget.audioUrl,
                  imageUrl: widget.imageUrl,
                ),
              ),
            ],
            if (widget.isPublic) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildReactionRow(),
            ],
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CroColors.deepWaypoint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionRow() {
    return Wrap(
      key: const Key('birdReactionRow'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final emoji in availableReactionEmojis)
          _buildReactionChip(emoji),
      ],
    );
  }

  Widget _buildReactionChip(String emoji) {
    final summary = _reactionFor(emoji);
    final count = summary?.count ?? 0;
    final reactedByMe = summary?.reactedByMe ?? false;
    return GestureDetector(
      key: Key('reactionChip_$emoji'),
      onTap: _isLoadingReactions ? null : () => _toggleReaction(emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: reactedByMe
              ? Theme.of(context).colorScheme.primaryContainer
              : CroColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabelValueRow(String label, String value, {required Key key}) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: CroColors.fog)),
        const Spacer(),
        Text(
          value,
          key: key,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CroColors.ink,
          ),
        ),
      ],
    );
  }
}
