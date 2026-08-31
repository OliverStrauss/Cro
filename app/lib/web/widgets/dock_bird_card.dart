import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';

enum BirdDockState { home, flight, away, hub }

/// Computed per-card view of one of the caller's own birds - resolved once per dock build
/// from the raw Bird plus whatever nest/hub it's currently associated with, so the card
/// itself never has to do lookups.
class DockBirdView {
  final Bird bird;
  final BirdDockState state;
  final String hostName;
  // Only set for BirdDockState.away (landed at a friend's nest) - names whose nest it's
  // parked at in the amber status chip, e.g. "At Jordan's nest".
  final String? hostUsername;
  final String hostInitial;
  final bool hostIsHub;
  final Color hostColor;
  final double progress;
  final String metaText;

  const DockBirdView({
    required this.bird,
    required this.state,
    required this.hostName,
    this.hostUsername,
    required this.hostInitial,
    required this.hostIsHub,
    required this.hostColor,
    required this.progress,
    required this.metaText,
  });

  /// Resolves a view for [bird] against the caller's own nests, friends' nests, and Hubs -
  /// or returns null if the bird's from/to/current id can't currently be placed anywhere
  /// (e.g. a stale race with a friend deleting a nest), matching MapScreen's own
  /// drop-rather-than-crash convention for unplaceable birds.
  static DockBirdView? resolve({
    required Bird bird,
    required List<Waypoint> ownNests,
    required List<Waypoint> friendWaypoints,
    required List<Hub> hubs,
  }) {
    final ownIds = ownNests.map((n) => n.id).toSet();

    Waypoint? waypointById(String? id) {
      if (id == null) return null;
      for (final n in ownNests) {
        if (n.id == id) return n;
      }
      for (final n in friendWaypoints) {
        if (n.id == id) return n;
      }
      return null;
    }

    Hub? hubById(String? id) {
      if (id == null) return null;
      for (final h in hubs) {
        if (h.id == id) return h;
      }
      return null;
    }

    if (bird.isTraveling) {
      final destNest = waypointById(bird.nestToId);
      final destHub = hubById(bird.nestToId);
      final name = destNest?.name ?? destHub?.name;
      if (name == null) return null;
      final color = destHub != null
          ? CroColors.deliveryAmber
          : (ownIds.contains(destNest!.id) ? CroColors.waypointBlue : hexToColor(destNest.color!));
      return DockBirdView(
        bird: bird,
        state: BirdDockState.flight,
        hostName: name,
        hostInitial: name.isEmpty ? '?' : name[0].toUpperCase(),
        hostIsHub: destHub != null,
        hostColor: color,
        progress: _flightProgress(bird),
        metaText: _etaText(bird),
      );
    }

    final currentNest = waypointById(bird.currentNestId);
    final currentHub = hubById(bird.currentNestId);
    if (currentHub != null) {
      return DockBirdView(
        bird: bird,
        state: BirdDockState.hub,
        hostName: currentHub.name,
        hostInitial: currentHub.name.isEmpty ? '?' : currentHub.name[0].toUpperCase(),
        hostIsHub: true,
        hostColor: CroColors.deliveryAmber,
        progress: 1,
        metaText: 'At a public hub',
      );
    }
    if (currentNest != null) {
      final isHome = ownIds.contains(currentNest.id);
      return DockBirdView(
        bird: bird,
        state: isHome ? BirdDockState.home : BirdDockState.away,
        hostName: currentNest.name,
        hostUsername: isHome ? null : currentNest.username,
        hostInitial: currentNest.name.isEmpty ? '?' : currentNest.name[0].toUpperCase(),
        hostIsHub: false,
        hostColor: isHome ? CroColors.waypointBlue : hexToColor(currentNest.color!),
        progress: 1,
        metaText: isHome ? 'Rested and ready to send' : 'Not your nest',
      );
    }
    return null;
  }

  static double _flightProgress(Bird bird) {
    final departed = bird.departedAt;
    final eta = bird.estimatedArrivalAt;
    if (departed == null || eta == null) return 0;
    final total = eta.difference(departed);
    if (total <= Duration.zero) return 1;
    final elapsed = DateTime.now().difference(departed);
    return (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  // No `intl` dependency in this project (see birds_screen.dart's _etaText) - a plain
  // relative countdown rather than a formatted timestamp.
  static String _etaText(Bird bird) {
    final eta = bird.estimatedArrivalAt;
    if (eta == null) return 'In flight';
    final remaining = eta.difference(DateTime.now());
    if (remaining.isNegative) return 'Arriving any moment';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return hours > 0 ? 'Arrives in ${hours}h ${minutes}m' : 'Arrives in ${minutes}m';
  }

  String get stateLabel => switch (state) {
    BirdDockState.home => 'Home',
    BirdDockState.flight => 'In flight',
    BirdDockState.away => hostUsername == null ? 'Away' : "At $hostUsername's nest",
    BirdDockState.hub => 'At a hub',
  };

  Color get stateColor => switch (state) {
    BirdDockState.home => CroColors.fog,
    BirdDockState.flight => CroColors.deepWaypoint,
    BirdDockState.away => CroColors.amberInk,
    BirdDockState.hub => CroColors.amberInk,
  };

  Color get cardBg => switch (state) {
    BirdDockState.home => Colors.white,
    BirdDockState.flight => const Color(0xFFF5FAFD),
    BirdDockState.away => const Color(0xFFFDF7F0),
    BirdDockState.hub => const Color(0xFFFDF7F0),
  };

  Color get cardBorder => switch (state) {
    BirdDockState.home => CroColors.ink.withValues(alpha: 0.1),
    BirdDockState.flight => CroColors.waypointBlue.withValues(alpha: 0.4),
    BirdDockState.away => CroColors.deliveryAmber.withValues(alpha: 0.45),
    BirdDockState.hub => CroColors.deliveryAmber.withValues(alpha: 0.45),
  };
}

/// One card in the "Your birds" dock - every bird in the caller's flock shows here
/// regardless of state, matching the design's "fixed roster, never a feed" intent.
class DockBirdCard extends StatelessWidget {
  final DockBirdView view;
  final VoidCallback onTap;
  final Widget? trailing;

  const DockBirdCard({super.key, required this.view, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('dockCard_${view.bird.id}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 168),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: view.cardBg,
          border: Border.all(color: view.cardBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        view.bird.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        view.stateLabel,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: view.stateColor),
                      ),
                    ],
                  ),
                ),
                if (!view.bird.isRead && view.state != BirdDockState.flight)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: CroColors.alertAway, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: view.hostColor,
                    borderRadius: BorderRadius.circular(view.hostIsHub ? 5 : 9),
                  ),
                  child: Text(
                    view.hostInitial,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    view.hostName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: view.progress,
                minHeight: 5,
                backgroundColor: CroColors.ink.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              view.metaText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: CroColors.fog),
            ),
            if (trailing != null) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 6)),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
