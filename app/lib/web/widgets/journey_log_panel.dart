import 'package:flutter/material.dart';

import '../../theme.dart';
import '../models/event.dart';

/// The right-hand panel's default view: every event ever recorded for the caller, newest
/// first, kept forever (see api/Models/Event.cs) - arrivals, departures, hub posts, friend
/// additions, flock milestones. Never paginated/pruned client-side either; GET /events'
/// `limit` query param is the only cap, matching the "kept for good" intent.
class JourneyLogPanel extends StatelessWidget {
  final List<AppEvent> events;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const JourneyLogPanel({
    super.key,
    required this.events,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Journey log', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text(
                'Every flight your flock has made, kept for good',
                style: TextStyle(fontSize: 12.5, color: CroColors.fog),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (isLoading) {
      return const Center(key: Key('journeyLogLoading'), child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return Center(
        key: const Key('journeyLogError'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (events.isEmpty) {
      return const Center(
        key: Key('journeyLogEmpty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing has happened yet - send your first bird to start the log.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CroColors.fog),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('journeyLogList'),
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        final isLast = i == events.length - 1;
        // IntrinsicHeight gives the connector's Expanded a bounded height to fill (this
        // row's own natural height) - without it, a ListView.builder item has no bounded
        // height to expand into, since each row shrink-wraps to its own content.
        return IntrinsicHeight(
          child: Row(
            key: Key('journeyEntry_${event.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            SizedBox(
              width: 12,
              child: Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _dotColor(event), shape: BoxShape.circle),
                  ),
                  if (!isLast) Expanded(child: Container(width: 2, color: CroColors.ink.withValues(alpha: 0.09))),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.displayText, style: const TextStyle(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 3),
                    Text(_relativeTime(event.createdAt), style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
                    if (event.quotedNote != null && event.quotedNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: CroColors.warmSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '"${event.quotedNote}"',
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ],
          ),
        );
      },
    );
  }

  Color _dotColor(AppEvent event) => switch (event.kind) {
    EventKind.birdDeparted => CroColors.alertAway,
    EventKind.birdArrived || EventKind.birdArrivedAtYourNest => CroColors.waypointBlue,
    EventKind.hubPostCreated => CroColors.deliveryAmber,
    EventKind.friendAdded || EventKind.friendRequestAccepted => CroColors.success,
    EventKind.birdJoinedFlock => CroColors.fog,
    _ => CroColors.fog,
  };

  // No `intl` dependency in this project - a plain relative-time string, same convention
  // as birds_screen.dart's ETA helper.
  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    final days = diff.inDays;
    return '$days day${days == 1 ? '' : 's'} ago';
  }
}
