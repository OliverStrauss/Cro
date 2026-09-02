import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../state/web_shell_controller.dart';
import 'dock_bird_card.dart';

const _maxBirdsPerUser = 5;

// Home, then away at a friend's nest, then at a hub, then flying to a nest, then flying to
// a hub - a bird settled somewhere reads before one still in the air, and within "still in
// the air" a nest-bound one reads before a hub-bound one. A manual bucket pass rather than
// List.sort: Dart's sort isn't guaranteed stable, and this keeps each bucket's own relative
// order (whatever _views/the API returned it in) instead of reshuffling it on every rebuild.
List<DockBirdView> _sortedForDock(List<DockBirdView> views) {
  int rank(DockBirdView v) => switch (v.state) {
    BirdDockState.home => 0,
    BirdDockState.away => 1,
    BirdDockState.hub => 2,
    BirdDockState.flight => v.hostIsHub ? 4 : 3,
  };
  final buckets = List.generate(5, (_) => <DockBirdView>[]);
  for (final v in views) {
    buckets[rank(v)].add(v);
  }
  return buckets.expand((b) => b).toList();
}

/// The persistent "Your birds" dock, overlaid on the content column (never the right
/// panel) on every screen. Every bird in the caller's flock shows here regardless of
/// state - a fixed roster, not a feed (see 01_web_shell_and_dock.md). Sorted home → away →
/// hub → flying-to-a-nest → flying-to-a-hub (see _sortedForDock). Can be put away entirely
/// (`hidden`) - it then collapses to a small "Show" pill instead (05_web_ui_updates.md item
/// 7); hidden/shown is independent of expanded/less-detail.
class YourBirdsDock extends StatelessWidget {
  final List<Bird> birds;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final DockFilter filter;
  final ValueChanged<DockFilter> onFilterChanged;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool hidden;
  final VoidCallback onHide;
  final VoidCallback onShow;
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
    required this.hidden,
    required this.onHide,
    required this.onShow,
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
    final summary = '$homeCount home · $flightCount flying · $awayCount away from your nests';

    if (hidden) {
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 22, bottom: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.34), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Material(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: const Key('dockShowPill'),
                borderRadius: BorderRadius.circular(14),
                onTap: onShow,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(color: CroColors.waypointBlue, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_forward_rounded, size: 11, color: CroColors.surface),
                    ),
                    const SizedBox(width: 10),
                    Text('Your birds', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13)),
                    const SizedBox(width: 10),
                    Text(summary, style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
                    const SizedBox(width: 10),
                    const Text('Show', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint)),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final filtered = _sortedForDock(views.where((v) {
      switch (filter) {
        case DockFilter.all:
          return true;
        case DockFilter.home:
          return v.state == BirdDockState.home;
        case DockFilter.away:
          return v.state != BirdDockState.home;
      }
    }).toList());

    return Container(
      key: const Key('yourBirdsDock'),
      margin: const EdgeInsets.only(left: 22, right: 22, bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
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
                  summary,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: CroColors.fog),
                ),
              ),
              for (final f in DockFilter.values) _FilterChip(filter: f, active: filter == f, onTap: () => onFilterChanged(f)),
              const SizedBox(width: 4),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('dockDetailToggle'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: onToggleExpanded,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      expanded ? 'Less detail' : 'More detail',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('dockHideButton'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: onHide,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Hide',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.fog),
                    ),
                  ),
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
                if (birds.length < _maxBirdsPerUser) _AddBirdCard(onTap: onComposePressed),
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
      child: Material(
        color: active ? CroColors.waypointBlue.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('dockFilter_${filter.name}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            // Padding grows the tap target beyond the visible chip (still a compact inline
            // toolbar control, but closer to a comfortable hit area than the original 5px).
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
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
      ),
    );
  }
}

class _AddBirdCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBirdCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('dockAddBirdCard'),
        borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }
}
