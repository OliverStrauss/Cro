import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../models/event.dart';
import '../state/web_shell_controller.dart';
import 'bird_panel_content.dart';
import 'hub_panel_content.dart';
import 'journey_log_panel.dart';
import 'nest_panel_content.dart';

/// The 392px right-hand panel: the journey log by default, swapping to a nest/hub/bird
/// detail body when one is selected (map marker tap, dock card tap).
class ContextPanel extends StatelessWidget {
  final PanelMode mode;
  final Waypoint? selectedNest;
  final bool selectedNestIsOwn;
  final Hub? selectedHub;
  final Bird? selectedBird;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
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
  final BirdReactionService reactionService;
  final VoidCallback onDataChanged;

  const ContextPanel({
    super.key,
    required this.mode,
    this.selectedNest,
    this.selectedNestIsOwn = false,
    this.selectedHub,
    this.selectedBird,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
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
    required this.reactionService,
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
        PanelMode.bird when selectedBird != null => BirdPanelContent(
          key: ValueKey('bird_${selectedBird!.id}'),
          bird: selectedBird!,
          ownNests: ownNests,
          friendWaypoints: friendWaypoints,
          hubs: hubs,
          authState: authState,
          reactionService: reactionService,
          onClose: onClose,
        ),
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
