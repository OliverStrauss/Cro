import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../models/event.dart';
import '../state/web_shell_controller.dart';
import 'hub_panel_content.dart';
import 'journey_log_panel.dart';
import 'nest_panel_content.dart';
import 'panel_header.dart';

/// The 392px right-hand panel: the journey log by default, swapping to a nest/hub/bird
/// summary when one is selected (map marker tap, dock card tap). Bird detail is still a
/// simple first pass here - reactions/payload/actions land in the compose PR; nest and hub
/// detail are the real thing (delivered mail, resident birds, the hub board).
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
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final BirdService birdService;
  final HubService hubService;
  final ProfileService profileService;
  final VoidCallback onDataChanged;

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
    required this.authState,
    required this.waypointService,
    required this.friendsService,
    required this.birdService,
    required this.hubService,
    required this.profileService,
    required this.onDataChanged,
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
        PanelMode.nest when selectedNest != null => NestPanelContent(
          key: ValueKey('nest_${selectedNest!.id}'),
          nest: selectedNest!,
          isOwn: selectedNestIsOwn,
          authState: authState,
          onClose: onClose,
          waypointService: waypointService,
          friendsService: friendsService,
          birdService: birdService,
          profileService: profileService,
          onChanged: onDataChanged,
        ),
        PanelMode.hub when selectedHub != null => HubPanelContent(
          key: ValueKey('hub_${selectedHub!.id}'),
          hub: selectedHub!,
          authState: authState,
          onClose: onClose,
          hubService: hubService,
          friendsService: friendsService,
        ),
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

class _BirdSummary extends StatelessWidget {
  final Bird bird;
  final VoidCallback onClose;

  const _BirdSummary({required this.bird, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
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
