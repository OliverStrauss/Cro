import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../models/event.dart';
import '../state/web_shell_controller.dart';
import 'journey_log_panel.dart';

/// The 392px right-hand panel: the journey log by default, swapping to a nest/hub/bird
/// summary when one is selected (map marker tap, dock card tap). The nest/hub/bird bodies
/// here are a deliberately simple first pass - dedicated, fuller panel content (delivered
/// birds, hub board, reactions) lands in later PRs; this pass just needs selecting
/// something on the map to show *something* sensible rather than nothing.
class ContextPanel extends StatelessWidget {
  final PanelMode mode;
  final Waypoint? selectedNest;
  final bool selectedNestIsOwn;
  final Hub? selectedHub;
  final Bird? selectedBird;
  final VoidCallback onClose;
  final List<AppEvent> events;
  final bool eventsLoading;
  final String? eventsError;
  final VoidCallback onRetryEvents;

  const ContextPanel({
    super.key,
    required this.mode,
    this.selectedNest,
    this.selectedNestIsOwn = false,
    this.selectedHub,
    this.selectedBird,
    required this.onClose,
    required this.events,
    required this.eventsLoading,
    required this.eventsError,
    required this.onRetryEvents,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('webContextPanel'),
      width: 392,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: CroColors.ink.withValues(alpha: 0.08))),
      ),
      child: switch (mode) {
        PanelMode.journeyLog => JourneyLogPanel(
          events: events,
          isLoading: eventsLoading,
          errorMessage: eventsError,
          onRetry: onRetryEvents,
        ),
        PanelMode.nest when selectedNest != null => _NestSummary(
          nest: selectedNest!,
          isOwn: selectedNestIsOwn,
          onClose: onClose,
        ),
        PanelMode.hub when selectedHub != null => _HubSummary(hub: selectedHub!, onClose: onClose),
        PanelMode.bird when selectedBird != null => _BirdSummary(bird: selectedBird!, onClose: onClose),
        _ => JourneyLogPanel(
          events: events,
          isLoading: eventsLoading,
          errorMessage: eventsError,
          onRetry: onRetryEvents,
        ),
      },
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _PanelHeader({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: CroColors.fog)),
              ],
            ),
          ),
          GestureDetector(
            key: const Key('webPanelClose'),
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: CroColors.fog),
          ),
        ],
      ),
    );
  }
}

class _NestSummary extends StatelessWidget {
  final Waypoint nest;
  final bool isOwn;
  final VoidCallback onClose;

  const _NestSummary({required this.nest, required this.isOwn, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final color = isOwn ? CroColors.waypointBlue : hexToColor(nest.color ?? '#6B7280');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          avatar: CircleAvatar(radius: 26, backgroundColor: color, child: const Icon(Icons.home, color: Colors.white)),
          title: isOwn ? 'Your nest' : "${nest.username}'s nest",
          subtitle: nest.name,
          onClose: onClose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            '(${nest.latitude.toStringAsFixed(4)}, ${nest.longitude.toStringAsFixed(4)})',
            style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
          ),
        ),
      ],
    );
  }
}

class _HubSummary extends StatelessWidget {
  final Hub hub;
  final VoidCallback onClose;

  const _HubSummary({required this.hub, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          avatar: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: CroColors.deliveryAmber, borderRadius: BorderRadius.circular(15)),
            child: Text(
              hub.name.isEmpty ? '?' : hub.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          title: hub.name,
          subtitle: '${hub.category ?? 'Landmark'} · anyone can send here',
          onClose: onClose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            '(${hub.latitude.toStringAsFixed(4)}, ${hub.longitude.toStringAsFixed(4)})',
            style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
          ),
        ),
      ],
    );
  }
}

class _BirdSummary extends StatelessWidget {
  final Bird bird;
  final VoidCallback onClose;

  const _BirdSummary({required this.bird, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          avatar: CircleAvatar(
            radius: 25,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ),
          title: bird.name,
          subtitle: '${bird.type} · ${BirdType.description(bird.type)}',
          onClose: onClose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            bird.isTraveling ? 'In flight' : 'Idle',
            style: const TextStyle(fontSize: 12.5, color: CroColors.fog),
          ),
        ),
      ],
    );
  }
}
