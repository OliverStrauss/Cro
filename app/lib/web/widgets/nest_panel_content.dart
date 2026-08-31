import 'package:flutter/material.dart';

import '../../models/bird.dart';
import '../../models/waypoint.dart';
import '../../services/bird_service.dart';
import '../../services/friends_service.dart';
import '../../services/profile_service.dart';
import '../../services/waypoint_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/received_bird_sheet.dart';
import '../../widgets/send_bird_dialog.dart';
import '../../widgets/waypoint_name_dialog.dart';
import 'panel_header.dart';

/// The nest detail panel body - own nests get delivered-mail + resident-bird sections
/// (rename, send onward). A friend's nest reuses that same resident-bird section (name,
/// type, "Send onward/home") for whichever of the caller's OWN birds happen to be resting
/// there right now - e.g. one you already sent this friend - and otherwise renders nothing
/// beyond the header, since a friend's nest never reveals anything else about what's there.
/// Adapted from the phone app's NestDetailsSheet (same resident-fetch/rename/send logic)
/// into the panel format instead of a bottom sheet.
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
  final FriendsService friendsService;
  final BirdService birdService;
  final ProfileService profileService;
  // Called after a successful rename/send so the shell can refresh its own nest/bird lists
  // (nav badges, dock, map markers) to match.
  final VoidCallback onChanged;

  const NestPanelContent({
    super.key,
    required this.nest,
    required this.isOwn,
    required this.ownBirds,
    required this.authState,
    required this.onClose,
    required this.waypointService,
    required this.friendsService,
    required this.birdService,
    required this.profileService,
    required this.onChanged,
  });

  @override
  State<NestPanelContent> createState() => _NestPanelContentState();
}

class _NestPanelContentState extends State<NestPanelContent> {
  late String _name = widget.nest.name;
  List<Bird> _residents = [];
  bool _isLoadingResidents = true;
  String? _currentUserId;

  List<Bird> get _ownIdleBirds => _residents.where((b) => b.userId == _currentUserId).toList();
  List<Bird> get _deliveredBirds => _residents.where((b) => b.userId != _currentUserId).toList();

  // Only meaningful for a friend's nest (isOwn's own body uses _ownIdleBirds instead, from
  // the cross-partition GET /waypoints/{id}/birds fetch, which also needs to see what
  // friends delivered - this list can't answer that).
  List<Bird> get _myBirdsHere =>
      widget.ownBirds.where((b) => b.currentNestId == widget.nest.id && !b.isTraveling).toList();

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
    }
  }

  @override
  void didUpdateWidget(covariant NestPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nest.id != widget.nest.id) {
      _name = widget.nest.name;
      _residents = [];
      _isLoadingResidents = widget.isOwn;
      if (widget.isOwn) _loadResidents();
    }
  }

  Future<void> _loadResidents() async {
    setState(() => _isLoadingResidents = true);
    try {
      final residents = await widget.birdService.getNestResidents(widget.authState.token!, widget.nest.id);
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
      token: widget.authState.token!,
      profileService: widget.profileService,
      birdService: widget.birdService,
    );
    if (!mounted) return;
    await _loadResidents();
    widget.onChanged();
  }

  Future<void> _openSendFlow(Bird bird) async {
    final token = widget.authState.token!;
    try {
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
      ]);
      final ownNests = results[0].where((w) => w.id != widget.nest.id);
      final friendNests = results[1].where((w) => w.id != widget.nest.id);
      final destinations = [
        ...ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)),
        ...friendNests.map((w) => SendBirdDestination(nestId: w.id, label: '${w.name} (${w.username})')),
      ];

      if (!mounted) return;
      final result = await showDialog<SendBirdResult>(
        context: context,
        builder: (_) => SendBirdDialog(destinations: destinations),
      );
      if (result == null) return;

      await widget.birdService.sendBird(token, bird.id, nestId: result.nestId, content: result.content);
      if (!mounted) return;
      setState(() => _residents = _residents.where((b) => b.id != bird.id).toList());
      widget.onChanged();
      _toast('${bird.name} is on its way!');
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Theme.of(context).colorScheme.error : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nest = widget.nest;
    final color = widget.isOwn ? CroColors.waypointBlue : hexToColor(nest.color ?? '#6B7280');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(
          avatar: CircleAvatar(radius: 26, backgroundColor: color, child: const Icon(Icons.home, color: Colors.white)),
          title: widget.isOwn ? 'Your nest' : "${nest.username}'s nest",
          subtitle: _name,
          onClose: widget.onClose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              Text(
                '(${nest.latitude.toStringAsFixed(4)}, ${nest.longitude.toStringAsFixed(4)})',
                style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
              ),
              if (widget.isOwn) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  key: const Key('webRenameNestButton'),
                  onTap: _rename,
                  child: const Text(
                    'Rename',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.isOwn) ...[
          const SizedBox(height: 16),
          Flexible(child: _ownBody()),
        ] else if (_myBirdsHere.isNotEmpty) ...[
          const SizedBox(height: 16),
          Flexible(child: _friendBirdsBody()),
        ],
      ],
    );
  }

  Widget _ownBody() {
    if (_isLoadingResidents) {
      return const Center(key: Key('nestPanelResidentsLoading'), child: CircularProgressIndicator());
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        if (_deliveredBirds.isNotEmpty) ...[
          const Text('Delivered to you', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          for (final bird in _deliveredBirds) _deliveredRow(bird),
          const SizedBox(height: 16),
        ],
        ..._birdsHereSection(_ownIdleBirds, title: 'Birds here'),
      ],
    );
  }

  // Only reached when _myBirdsHere is non-empty (see build()) - e.g. Oliver viewing Annie's
  // nest, where a bird he already sent her is currently resting. Reuses the exact same row
  // + send flow as an own nest's "Birds here" - the same "send home or onward" action works
  // unchanged since _openSendFlow already excludes whichever nest the bird is currently at
  // (this one) from both the own- and friend-nest destination lists.
  Widget _friendBirdsBody() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: _birdsHereSection(_myBirdsHere, title: 'Your birds here'),
    );
  }

  List<Widget> _birdsHereSection(List<Bird> birds, {required String title}) {
    return [
      Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 9),
      if (birds.isEmpty)
        const Text('This nest is empty', key: Key('nestPanelEmpty'), style: TextStyle(fontSize: 12.5, color: CroColors.fog))
      else
        for (final bird in birds) _residentRow(bird),
    ];
  }

  Widget _deliveredRow(Bird bird) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: Key('nestPanelDelivered_${bird.id}'),
        onTap: () => _openReceivedBird(bird),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF7F0),
            border: Border.all(color: CroColors.deliveryAmber.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bird.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      bird.updatedAt == null
                          ? (bird.isRead ? bird.type : 'New · ${bird.type}')
                          : '${bird.isRead ? bird.type : 'New · ${bird.type}'} · ${_relativeTime(bird.updatedAt!)}',
                      style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                    ),
                  ],
                ),
              ),
              const Text('Read', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: CroColors.amberInk)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _residentRow(Bird bird) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: Key('nestPanelResident_${bird.id}'),
        onTap: () => _openSendFlow(bird),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: CroColors.warmSurface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Container(width: 28, height: 28, decoration: const BoxDecoration(color: CroColors.waypointBlue, shape: BoxShape.circle)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bird.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      bird.updatedAt == null ? bird.type : '${bird.type} · ${_relativeTime(bird.updatedAt!)}',
                      style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                    ),
                  ],
                ),
              ),
              const Text('Send →', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
            ],
          ),
        ),
      ),
    );
  }
}
