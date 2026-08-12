import 'package:flutter/material.dart';

import '../theme.dart';

// Bottom sheet shown when tapping a moving bird marker on the map - same chrome as
// NestDetailsSheet, but purely informational (no rename/upload/send actions): who sent the
// bird, where it's headed, and how far along its journey it is. Stateless because every
// field is a snapshot of already-resolved data (MapScreen's _TravelingBird) rather than
// something this sheet fetches or mutates itself.
class BirdDetailsSheet extends StatelessWidget {
  final String name;
  final String type;
  // "You" for the caller's own bird, the friend's username for a friend's.
  final String senderLabel;
  final Color color;
  final String destinationName;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;

  const BirdDetailsSheet({
    super.key,
    required this.name,
    required this.type,
    required this.senderLabel,
    required this.color,
    required this.destinationName,
    required this.departedAt,
    required this.estimatedArrivalAt,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required String type,
    required String senderLabel,
    required Color color,
    required String destinationName,
    required DateTime departedAt,
    required DateTime estimatedArrivalAt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BirdDetailsSheet(
        name: name,
        type: type,
        senderLabel: senderLabel,
        color: color,
        destinationName: destinationName,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
      ),
    );
  }

  // Same relative-countdown shape as BirdsScreen._etaText - no `intl` dependency in this
  // project, so a plain "arrives in Xh Ym" rather than a formatted timestamp.
  String get _etaText {
    final remaining = estimatedArrivalAt.difference(DateTime.now());
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
    final totalDuration = estimatedArrivalAt.difference(departedAt);
    if (totalDuration <= Duration.zero) {
      return 1.0;
    }
    final fraction =
        DateTime.now().difference(departedAt).inMilliseconds /
        totalDuration.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
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
                    color: color,
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
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: CroColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$type · Sent by $senderLabel',
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
              destinationName,
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
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
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
