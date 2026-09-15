import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/pinned_bird.dart';
import '../../models/waypoint.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/pin_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/received_bird_sheet.dart';
import '../../widgets/waypoint_name_dialog.dart';
import 'coordinate_readout.dart';
import 'hover_lift.dart';
import 'panel_header.dart';
import 'pinned_message_card.dart';

/// The nest detail panel body - own nests get delivered-mail + resident-bird sections
/// (rename, tap a resident to open its bird detail panel). A friend's nest reuses that same
/// resident-bird section for whichever of the caller's OWN birds happen to be resting there
/// right now - e.g. one you already sent this friend - and otherwise renders nothing beyond
/// the header, since a friend's nest never reveals anything else about what's there.
/// Adapted from the phone app's NestDetailsSheet (same resident-fetch/rename logic) into the
/// panel format instead of a bottom sheet.
class NestPanelContent extends StatefulWidget {
  final Waypoint nest;
  final bool isOwn;
  // The caller's full own-bird list (already loaded shell-wide) - used only for a friend's
  // nest, to find which of the caller's own birds are currently parked there without needing
  // a separate fetch (GET /waypoints/{id}/birds is owner-gated, so it can't be called for a
  // nest that isn't the caller's own).
  final List<Bird> ownBirds;
  final AuthState authState;
  final VoidCallback onClose;
  final WaypointService waypointService;
  final BirdService birdService;
  final ProfileService profileService;
  final PinService pinService;
  final FriendsService friendsService;
  // Called after a successful rename so the shell can refresh its own nest/bird lists (nav
  // badges, dock, map markers) to match.
  final VoidCallback onChanged;
  // Opens a resident bird's own detail panel - the same one YourBirdsDock opens for a dock
  // tap - instead of this panel offering its own send flow.
  final ValueChanged<Bird> onSelectBird;
  // Own nest only - jumps to the Pinned screen (see WebPinnedScreen), same "jump to the tab
  // that actually shows it" pattern as ContextPanel's onFollowOnMap.
  final VoidCallback onViewPinned;

  const NestPanelContent({
    super.key,
    required this.nest,
    required this.isOwn,
    required this.ownBirds,
    required this.authState,
    required this.onClose,
    required this.waypointService,
    required this.birdService,
    required this.profileService,
    required this.pinService,
    required this.friendsService,
    required this.onChanged,
    required this.onSelectBird,
    required this.onViewPinned,
  });

  @override
  State<NestPanelContent> createState() => _NestPanelContentState();
}

class _NestPanelContentState extends State<NestPanelContent> {
  late String _name = widget.nest.name;
  List<Bird> _residents = [];
  bool _isLoadingResidents = true;
  String? _currentUserId;
  // Only loaded for a friend's nest - this user's own public pins, filtered client-side from
  // the same world feed WebPinnedScreen's Public tab shows (no per-user endpoint exists, and
  // the whole feed is small enough that a second cross-partition scan isn't worth adding).
  List<PinnedBird> _publicPins = [];
  bool _isLoadingPublicPins = true;

  List<Bird> get _ownIdleBirds =>
      _residents.where((b) => b.userId == _currentUserId).toList();
  List<Bird> get _deliveredBirds =>
      _residents.where((b) => b.userId != _currentUserId).toList();

  // Only meaningful for a friend's nest (isOwn's own body uses _ownIdleBirds instead, from
  // the cross-partition GET /waypoints/{id}/birds fetch, which also needs to see what
  // friends delivered - this list can't answer that).
  List<Bird> get _myBirdsHere => widget.ownBirds
      .where((b) => b.currentNestId == widget.nest.id && !b.isTraveling)
      .toList();

  // Both lists come back from GET /waypoints/{id}/birds already newest-arrival-first (see
  // BirdService.GetNestResidentsAsync's OrderByDescending(UpdatedAt)) - same relative-time
  // convention as hub_message_card.dart's _relativeTime.
  String _relativeTime(DateTime time) {
    final elapsed = DateTime.now().difference(time);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  @override
  void initState() {
    super.initState();
    _name = widget.nest.name;
    if (widget.isOwn) {
      _currentUserId = jwtSubject(widget.authState.token!);
      _loadResidents();
    } else {
      _loadPublicPins();
    }
  }

  @override
  void didUpdateWidget(covariant NestPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nest.id != widget.nest.id) {
      _name = widget.nest.name;
      _residents = [];
      _isLoadingResidents = widget.isOwn;
      _publicPins = [];
      _isLoadingPublicPins = !widget.isOwn;
      if (widget.isOwn) {
        _loadResidents();
      } else {
        _loadPublicPins();
      }
    }
  }

  Future<void> _loadPublicPins() async {
    setState(() => _isLoadingPublicPins = true);
    try {
      final allPublicPins = await widget.pinService.listPublicPins(
        widget.authState.token!,
      );
      if (!mounted) return;
      setState(() {
        _publicPins = allPublicPins
            .where((p) => p.receiverId == widget.nest.userId)
            .toList();
        _isLoadingPublicPins = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingPublicPins = false);
    }
  }

  Future<void> _loadResidents() async {
    setState(() => _isLoadingResidents = true);
    try {
      final residents = await widget.birdService.getNestResidents(
        widget.authState.token!,
        widget.nest.id,
      );
      if (!mounted) return;
      setState(() {
        _residents = residents;
        _isLoadingResidents = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingResidents = false);
    }
  }

  Future<void> _rename() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(initialName: _name),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;

    try {
      await widget.waypointService.updateWaypoint(
        widget.authState.token!,
        widget.nest.id,
        name: newName.trim(),
        latitude: widget.nest.latitude,
        longitude: widget.nest.longitude,
      );
      if (!mounted) return;
      setState(() => _name = newName.trim());
      widget.onChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _openReceivedBird(Bird bird) async {
    await ReceivedBirdSheet.show(
      context,
      birdId: bird.id,
      name: bird.name,
      type: bird.type,
      senderId: bird.userId,
      content: bird.content,
      audioUrl: bird.audioUrl,
      imageUrl: bird.imageUrl,
      isRead: bird.isRead,
      isPublic: bird.isPublic,
      token: widget.authState.token!,
      profileService: widget.profileService,
      birdService: widget.birdService,
      pinService: widget.pinService,
    );
    if (!mounted) return;
    await _loadResidents();
    widget.onChanged();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nest = widget.nest;
    final color = widget.isOwn
        ? CroColors.waypointBlue
        : hexToColor(nest.color ?? '#6B7280');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(
          avatar: CircleAvatar(
            radius: 26,
            backgroundColor: color,
            child: const Icon(Icons.home, color: CroColors.surface),
          ),
          title: widget.isOwn ? 'Your nest' : "${nest.username}'s nest",
          subtitle: _name,
          onClose: widget.onClose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              CoordinateReadout(
                latitude: nest.latitude,
                longitude: nest.longitude,
              ),
              if (widget.isOwn) ...[
                const SizedBox(width: 10),
                _headerLink('webRenameNestButton', 'Rename', _rename),
                const SizedBox(width: 10),
                _headerLink(
                  'webViewPinnedNestButton',
                  'View pinned',
                  widget.onViewPinned,
                ),
              ],
            ],
          ),
        ),
        if (widget.isOwn) ...[
          const SizedBox(height: 16),
          Flexible(child: _ownBody()),
        ] else ...[
          const SizedBox(height: 16),
          Flexible(child: _otherBody()),
        ],
      ],
    );
  }

  Widget _headerLink(String key, String label, VoidCallback onTap) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key(key),
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            label,
            style: CroTextStyles.label(size: 11, color: CroColors.deepWaypoint),
          ),
        ),
      ),
    );
  }

  Widget _ownBody() {
    if (_isLoadingResidents) {
      return const Center(
        key: Key('nestPanelResidentsLoading'),
        child: CircularProgressIndicator(),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        if (_deliveredBirds.isNotEmpty) ...[
          Text('Delivered to you', style: CroTextStyles.label(size: 12)),
          const SizedBox(height: 9),
          for (final bird in _deliveredBirds) _deliveredRow(bird),
          const SizedBox(height: 16),
        ],
        ..._birdsHereSection(_ownIdleBirds, title: 'Birds here'),
      ],
    );
  }

  // A friend's (or any other user's) nest: "Your birds here" only when non-empty - e.g.
  // Oliver viewing Annie's nest, where a bird he already sent her is currently resting.
  // Reuses the exact same row as an own nest's "Birds here" - tapping it opens that bird's
  // own detail panel. Below that, this user's public pins - styled as a board list (same
  // PinnedMessageCard/"the board" pattern HubPanelContent and WebPinnedScreen's Public tab
  // already use), read-only here: taking a pin down is only ever offered from the Pinned
  // screen itself.
  Widget _otherBody() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        if (_myBirdsHere.isNotEmpty) ...[
          ..._birdsHereSection(_myBirdsHere, title: 'Your birds here'),
          const SizedBox(height: 16),
        ],
        Text('Public pins', style: CroTextStyles.label(size: 12)),
        const SizedBox(height: 9),
        Column(
          key: const Key('nestPanelPublicPinsList'),
          children: _publicPinsSection(),
        ),
      ],
    );
  }

  List<Widget> _publicPinsSection() {
    if (_isLoadingPublicPins) {
      return [
        const Center(
          key: Key('nestPanelPublicPinsLoading'),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    if (_publicPins.isEmpty) {
      return [
        Text(
          'No public pins yet',
          key: const Key('nestPanelPublicPinsEmpty'),
          style: CroTextStyles.data(size: 12.5),
        ),
      ];
    }
    return [
      for (final pin in _publicPins)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PinnedMessageCard(
            key: ValueKey('nestPanelPublicPin_${pin.id}'),
            pin: pin,
            showAddFriend: false,
            token: widget.authState.token!,
            friendsService: widget.friendsService,
          ),
        ),
    ];
  }

  List<Widget> _birdsHereSection(List<Bird> birds, {required String title}) {
    return [
      Text(title, style: CroTextStyles.label(size: 12)),
      const SizedBox(height: 9),
      if (birds.isEmpty)
        Text(
          'This nest is empty',
          key: const Key('nestPanelEmpty'),
          style: CroTextStyles.data(size: 12.5),
        )
      else
        for (final bird in birds) _residentRow(bird),
    ];
  }

  Widget _deliveredRow(Bird bird) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverLift(
        builder: (context, hovering) => Material(
          color: CroColors.warmTint,
          elevation: hovering ? 2 : 0,
          shadowColor: CroColors.ink.withValues(alpha: 0.25),
          borderRadius: CroBorders.radius,
          child: InkWell(
            key: Key('nestPanelDelivered_${bird.id}'),
            borderRadius: CroBorders.radius,
            onTap: () => _openReceivedBird(bird),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(
                  color: CroColors.deliveryAmber.withValues(alpha: 0.6),
                ),
                borderRadius: CroBorders.radius,
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: CroColors.surface,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bird.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          bird.updatedAt == null
                              ? (bird.isRead ? bird.type : 'New · ${bird.type}')
                              : '${bird.isRead ? bird.type : 'New · ${bird.type}'} · ${_relativeTime(bird.updatedAt!)}',
                          style: CroTextStyles.data(size: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Text('Read', style: CroTextStyles.stamp()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _residentRow(Bird bird) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverLift(
        builder: (context, hovering) => Material(
          color: CroColors.warmSurface,
          elevation: hovering ? 2 : 0,
          shadowColor: CroColors.ink.withValues(alpha: 0.25),
          borderRadius: CroBorders.radius,
          child: InkWell(
            key: Key('nestPanelResident_${bird.id}'),
            borderRadius: CroBorders.radius,
            onTap: () => widget.onSelectBird(bird),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: CroColors.waypointBlue,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.flutter_dash,
                      size: 14,
                      color: CroColors.surface,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bird.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          bird.updatedAt == null
                              ? bird.type
                              : '${bird.type} · ${_relativeTime(bird.updatedAt!)}',
                          style: CroTextStyles.data(size: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: CroColors.fog,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
