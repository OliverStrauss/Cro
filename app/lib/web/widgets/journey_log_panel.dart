import 'package:flutter/material.dart';

import '../../theme.dart';
import '../models/event.dart';

/// The top bar's journey log popup: every event ever recorded for the caller, newest first,
/// kept forever (see api/Models/Event.cs) - arrivals, departures, hub posts, friend
/// additions, flock milestones. Never paginated/pruned client-side either; GET /events'
/// `limit` query param is the only cap, matching the "kept for good" intent.
///
/// This used to be the right-hand context panel's permanent default view; it's now an
/// overlay anchored to a top-bar button (see TopBar), so the panel only mounts for a
/// selected nest/hub/bird. Sizing here is one step down from that old panel version (this
/// popup is narrower, 380px vs. 392px with panel padding).
class JourneyLogPanel extends StatelessWidget {
  final List<AppEvent> events;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const JourneyLogPanel({
    super.key,
    required this.events,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: CroColors.ink.withValues(alpha: 0.07))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Journey log', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text('Every flight your flock has made', style: TextStyle(fontSize: 11.5, color: CroColors.fog)),
                  ],
                ),
              ),
              GestureDetector(
                key: const Key('webJourneyLogClose'),
                onTap: onClose,
                child: const Icon(Icons.close, size: 16, color: CroColors.fog),
              ),
            ],
          ),
        ),
        Flexible(child: _body(context)),
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
      // shrinkWrap so the popup sizes to its content (up to the 62vh cap the overlay imposes)
      // rather than always filling it - matches the notifications dropdown's sizing.
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
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
              width: 10,
              child: Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: _dotColor(event), shape: BoxShape.circle),
                  ),
                  if (!isLast) Expanded(child: Container(width: 2, color: CroColors.ink.withValues(alpha: 0.09))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.displayText, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                    const SizedBox(height: 3),
                    Text(_relativeTime(event.createdAt), style: const TextStyle(fontSize: 11, color: CroColors.fog)),
                    if (event.quotedNote != null && event.quotedNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: CroColors.warmSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '"${event.quotedNote}"',
                          style: const TextStyle(fontSize: 11.5, height: 1.5),
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
