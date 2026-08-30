import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../state/web_shell_controller.dart';
import 'dock_bird_card.dart';

/// The persistent "Your birds" dock, overlaid on the content column (never the right
/// panel) on every screen. Every bird in the caller's flock shows here regardless of
/// state - a fixed roster, not a feed (see 01_web_shell_and_dock.md).
class YourBirdsDock extends StatelessWidget {
  final List<Bird> birds;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final DockFilter filter;
  final ValueChanged<DockFilter> onFilterChanged;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Bird> onBirdTap;
  final VoidCallback onComposePressed;

  const YourBirdsDock({
    super.key,
    required this.birds,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
    required this.filter,
    required this.onFilterChanged,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onBirdTap,
    required this.onComposePressed,
  });

  List<DockBirdView> get _views => birds
      .map((b) => DockBirdView.resolve(bird: b, ownNests: ownNests, friendWaypoints: friendWaypoints, hubs: hubs))
      .whereType<DockBirdView>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final views = _views;
    final homeCount = views.where((v) => v.state == BirdDockState.home).length;
    final flightCount = views.where((v) => v.state == BirdDockState.flight).length;
    final awayCount = views.length - homeCount - flightCount;

    final filtered = views.where((v) {
      switch (filter) {
        case DockFilter.all:
          return true;
        case DockFilter.home:
          return v.state == BirdDockState.home;
        case DockFilter.away:
          return v.state != BirdDockState.home;
      }
    }).toList();

    return Container(
      key: const Key('yourBirdsDock'),
      margin: const EdgeInsets.only(left: 22, right: 22, bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: CroColors.ink.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your birds', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$homeCount home · $flightCount flying · $awayCount away from your nests',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: CroColors.fog),
                ),
              ),
              for (final f in DockFilter.values) _FilterChip(filter: f, active: filter == f, onTap: () => onFilterChanged(f)),
              const SizedBox(width: 4),
              GestureDetector(
                key: const Key('dockDetailToggle'),
                onTap: onToggleExpanded,
                child: Text(
                  expanded ? 'Less detail' : 'More detail',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: expanded ? 200 : 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final v in filtered)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 180,
                      child: DockBirdCard(
                        view: v,
                        onTap: () => onBirdTap(v.bird),
                        trailing: expanded
                            ? Text(
                                '${v.bird.type} · ${BirdType.description(v.bird.type)}',
                                style: const TextStyle(fontSize: 11, color: CroColors.fog),
                              )
                            : null,
                      ),
                    ),
                  ),
                _AddBirdCard(onTap: onComposePressed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final DockFilter filter;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({required this.filter, required this.active, required this.onTap});

  String get _label => switch (filter) {
    DockFilter.all => 'All',
    DockFilter.away => 'Away',
    DockFilter.home => 'Home',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        key: Key('dockFilter_${filter.name}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? CroColors.waypointBlue.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: active ? CroColors.deepWaypoint : CroColors.fog,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddBirdCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBirdCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('dockAddBirdCard'),
      onTap: onTap,
      child: Container(
        width: 124,
        decoration: BoxDecoration(
          border: Border.all(color: CroColors.ink.withValues(alpha: 0.2), width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 22, color: CroColors.fog),
            SizedBox(height: 5),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Send a new bird',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: CroColors.fog),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
