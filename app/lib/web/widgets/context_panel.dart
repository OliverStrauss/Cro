import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/friend_bird.dart';
import '../../models/hub.dart';
import '../../models/public_bird.dart';
import '../../models/waypoint.dart';
import '../../services/bird_reaction_service.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../state/web_shell_controller.dart';
import 'bird_panel_content.dart';
import 'friend_bird_panel_content.dart';
import 'hub_panel_content.dart';
import 'nest_panel_content.dart';
import 'public_bird_panel_content.dart';

/// The 392px right-hand panel: only mounted while a nest, hub or bird is selected (map
/// marker tap, dock card tap, nests/hubs screen tap) - there is no "nothing selected" state
/// to render here.
class ContextPanel extends StatelessWidget {
  final PanelMode mode;
  final Waypoint? selectedNest;
  final bool selectedNestIsOwn;
  final Hub? selectedHub;
  final Bird? selectedBird;
  final FriendBird? selectedFriendBird;
  final PublicBird? selectedPublicBird;
  // The caller's own full bird list - only used by NestPanelContent, to find which of the
  // caller's own birds are currently resting at a friend's nest (see its own doc comment).
  final List<Bird> ownBirds;
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Hub> hubs;
  final VoidCallback onClose;
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final BirdService birdService;
  final HubService hubService;
  final ProfileService profileService;
  final BirdReactionService reactionService;
  final VoidCallback onDataChanged;
  final VoidCallback onFollowOnMap;
  final ValueChanged<Bird> onSelectBird;

  const ContextPanel({
    super.key,
    required this.mode,
    this.selectedNest,
    this.selectedNestIsOwn = false,
    this.selectedHub,
    this.selectedBird,
    this.selectedFriendBird,
    this.selectedPublicBird,
    required this.ownBirds,
    required this.ownNests,
    required this.friendWaypoints,
    required this.hubs,
    required this.onClose,
    required this.authState,
    required this.waypointService,
    required this.friendsService,
    required this.birdService,
    required this.hubService,
    required this.profileService,
    required this.reactionService,
    required this.onDataChanged,
    required this.onFollowOnMap,
    required this.onSelectBird,
  });

  @override
  Widget build(BuildContext context) {
    // Floats over the map (see WebShellScreen) rather than sitting in its own Row column,
    // so rounded corners + a shadow read as a card over the map instead of a flush-edge
    // sidebar - same floating-card language as FloatingActionsCluster.
    return Container(
      key: const Key('webContextPanel'),
      width: 392,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
        boxShadow: [BoxShadow(color: CroColors.ink.withValues(alpha: 0.14), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: switch (mode) {
        PanelMode.nest when selectedNest != null => NestPanelContent(
          key: ValueKey('nest_${selectedNest!.id}'),
          nest: selectedNest!,
          isOwn: selectedNestIsOwn,
          ownBirds: ownBirds,
          authState: authState,
          onClose: onClose,
          waypointService: waypointService,
          birdService: birdService,
          profileService: profileService,
          onChanged: onDataChanged,
          onSelectBird: onSelectBird,
        ),
        PanelMode.hub when selectedHub != null => HubPanelContent(
          key: ValueKey('hub_${selectedHub!.id}'),
          hub: selectedHub!,
          authState: authState,
          onClose: onClose,
          hubService: hubService,
          friendsService: friendsService,
          profileService: profileService,
        ),
        PanelMode.bird when selectedBird != null => BirdPanelContent(
          key: ValueKey('bird_${selectedBird!.id}'),
          bird: selectedBird!,
          ownNests: ownNests,
          friendWaypoints: friendWaypoints,
          hubs: hubs,
          authState: authState,
          reactionService: reactionService,
          birdService: birdService,
          onClose: onClose,
          onDataChanged: onDataChanged,
          onFollowOnMap: onFollowOnMap,
        ),
        PanelMode.friendBird when selectedFriendBird != null => FriendBirdPanelContent(
          key: ValueKey('friendBird_${selectedFriendBird!.id}'),
          bird: selectedFriendBird!,
          ownNests: ownNests,
          friendWaypoints: friendWaypoints,
          hubs: hubs,
          authState: authState,
          reactionService: reactionService,
          onClose: onClose,
          onFollowOnMap: onFollowOnMap,
        ),
        PanelMode.publicBird when selectedPublicBird != null => PublicBirdPanelContent(
          key: ValueKey('publicBird_${selectedPublicBird!.id}'),
          bird: selectedPublicBird!,
          authState: authState,
          friendsService: friendsService,
          onClose: onClose,
        ),
        // Defensive only: the shell never mounts ContextPanel unless a selection backs
        // `mode` (see WebShellScreen), so this can't actually be reached.
        _ => const SizedBox.shrink(),
      },
    );
  }
}
