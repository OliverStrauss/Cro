import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../widgets/avatar_with_fallback.dart';
import 'hover_lift.dart';

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
          : (ownIds.contains(destNest!.id)
                ? CroColors.waypointBlue
                : hexToColor(destNest.color!));
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
        hostInitial: currentHub.name.isEmpty
            ? '?'
            : currentHub.name[0].toUpperCase(),
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
        hostInitial: currentNest.name.isEmpty
            ? '?'
            : currentNest.name[0].toUpperCase(),
        hostIsHub: false,
        hostColor: isHome
            ? CroColors.waypointBlue
            : hexToColor(currentNest.color!),
        progress: 1,
        metaText: isHome ? 'At Nest' : 'Not your nest',
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
    return hours > 0
        ? 'Arrives in ${hours}h ${minutes}m'
        : 'Arrives in ${minutes}m';
  }

  String get stateLabel => switch (state) {
    BirdDockState.home => 'Home',
    BirdDockState.flight => 'In flight',
    BirdDockState.away =>
      hostUsername == null ? 'Away' : "At $hostUsername's nest",
    BirdDockState.hub => 'At a hub',
  };

  Color get stateColor => switch (state) {
    BirdDockState.home => CroColors.fog,
    BirdDockState.flight => CroColors.deepWaypoint,
    BirdDockState.away => CroColors.amberInk,
    BirdDockState.hub => CroColors.amberInk,
  };

  Color get cardBg => switch (state) {
    BirdDockState.home => CroColors.surface,
    BirdDockState.flight => CroColors.flightTint,
    BirdDockState.away => CroColors.warmTint,
    BirdDockState.hub => CroColors.warmTint,
  };

  Color get cardBorder => switch (state) {
    BirdDockState.home => CroColors.ink.withValues(alpha: 0.1),
    BirdDockState.flight => CroColors.waypointBlue.withValues(alpha: 0.5),
    BirdDockState.away => CroColors.deliveryAmber.withValues(alpha: 0.5),
    BirdDockState.hub => CroColors.deliveryAmber.withValues(alpha: 0.5),
  };

  // State reads in line weight too, not color alone (see the direction contract's
  // emission-line-rail raise): a bird actually in motion gets a bolder ruled edge than one
  // settled somewhere, so the state is legible even without color vision.
  double get cardBorderWidth => state == BirdDockState.flight ? 2 : 1;
}

/// One card in the "Your birds" dock - every bird in the caller's flock shows here
/// regardless of state, matching the design's "fixed roster, never a feed" intent.
class DockBirdCard extends StatefulWidget {
  final DockBirdView view;
  final VoidCallback onTap;
  final Widget? trailing;
  // True for exactly one poll cycle right after this bird flips from traveling to
  // arrived - see WebShellData.justArrivedBirdIds. Triggers a one-shot amber flash.
  final bool justArrived;

  const DockBirdCard({
    super.key,
    required this.view,
    required this.onTap,
    this.trailing,
    this.justArrived = false,
  });

  @override
  State<DockBirdCard> createState() => _DockBirdCardState();
}

class _DockBirdCardState extends State<DockBirdCard>
    with TickerProviderStateMixin {
  late final AnimationController _flashController;
  late final AnimationController _pulseController;
  late final Animation<double> _flashScale;
  late final Animation<double> _flashGlow;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final flashCurve = CurvedAnimation(
      parent: _flashController,
      curve: Curves.easeOut,
    );
    _flashScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 65),
    ]).animate(flashCurve);
    _flashGlow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 80),
    ]).animate(flashCurve);
    if (widget.justArrived) _flashController.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant DockBirdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.justArrived && !oldWidget.justArrived) {
      _flashController.forward(from: 0);
    }
    _syncPulse();
  }

  // Same "reduce motion" convention as WebMapScreen._syncBob - both loops are purely
  // decorative, so they're skipped rather than given a reduced-motion variant.
  void _syncPulse() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shouldPulse =
        !reduceMotion &&
        !widget.view.bird.isRead &&
        widget.view.state != BirdDockState.flight;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return HoverLift(
      builder: (context, hovering) => AnimatedBuilder(
        animation: Listenable.merge([_flashController, _pulseController]),
        builder: (context, child) {
          final glow = _flashGlow.value;
          final borderColor = Color.lerp(
            view.cardBorder,
            CroColors.deliveryAmber,
            glow,
          )!;
          final unreadOpacity = _pulseController.isAnimating
              ? 1.0 - (_pulseController.value * 0.55)
              : 1.0;
          return Transform.scale(
            scale: _flashScale.value,
            child: Material(
              color: view.cardBg,
              elevation: hovering ? 3 : 0,
              shadowColor: CroColors.ink.withValues(alpha: 0.25),
              borderRadius: CroBorders.radius,
              child: InkWell(
                key: Key('dockCard_${view.bird.id}'),
                borderRadius: CroBorders.radius,
                onTap: widget.onTap,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 168),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: borderColor,
                      width: view.cardBorderWidth + glow * 1.5,
                    ),
                    borderRadius: CroBorders.radius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          AvatarWithFallback(
                            imageUrl: view.bird.profilePictureUrl,
                            initialsSource: view.bird.name,
                            radius: 16,
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
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                Text(
                                  view.stateLabel,
                                  style: CroTextStyles.label(
                                    size: 10,
                                    color: view.stateColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!view.bird.isRead &&
                              view.state != BirdDockState.flight)
                            Opacity(
                              opacity: unreadOpacity,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: CroColors.alertAway,
                                  shape: BoxShape.circle,
                                ),
                              ),
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
                              borderRadius: BorderRadius.circular(
                                view.hostIsHub ? 5 : 9,
                              ),
                            ),
                            child: Text(
                              view.hostInitial,
                              style: CroTextStyles.label(
                                size: 9,
                                color: CroColors.surface,
                              ),
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
                        borderRadius: CroBorders.radiusSmall,
                        child: LinearProgressIndicator(
                          value: view.progress,
                          minHeight: 5,
                          backgroundColor: CroColors.ink.withValues(
                            alpha: 0.08,
                          ),
                          valueColor: AlwaysStoppedAnimation(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        view.metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CroTextStyles.data(size: 11),
                      ),
                      if (widget.trailing != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                        ),
                        widget.trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
