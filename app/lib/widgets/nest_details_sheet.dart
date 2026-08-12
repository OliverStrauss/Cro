import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../utils/jwt_utils.dart';
import 'avatar_with_fallback.dart';
import 'received_bird_sheet.dart';
import 'send_bird_dialog.dart';
import 'waypoint_name_dialog.dart';

// Bottom-sheet replacement for the old NestDetailsDialog - same shared popup shown when
// tapping either one of the user's own nest markers or a friend's nest marker on the map:
// bordered profile picture, "Your nest" (for the user's own marker) or "{username}'s nest"
// (for a friend's) title, the name the owner gave that nest, and lat/long formatted to 4
// decimal places - same shape for both, so a friend's nest never looks meaningfully
// different from your own. Own nests additionally get an editable name/picture (tap either
// to change them), a "Delivered to you" section for birds someone else sent that landed
// here (tap to read the message; the backend only allows resending a bird from the
// partition of whoever originally sent it, so these are read-only), and a "Birds here"
// section listing the caller's own idle birds currently parked at this nest, which can be
// resent onward. Presented as a swipe-dismissible sheet instead of a centered modal;
// behavior is otherwise unchanged.
class NestDetailsSheet extends StatefulWidget {
  final String username;
  final bool isOwn;
  final String? profilePictureUrl;
  final String waypointId;
  final String waypointName;
  final double latitude;
  final double longitude;
  final AuthState authState;
  // Avatar ring color: fixed Waypoint blue for the user's own nest, the friend's existing
  // server-assigned color otherwise - same rule the map markers already use.
  final Color ringColor;
  // Optimistic initial value shown while this sheet fetches the full resident list itself
  // (own idle birds plus anything delivered from someone else) - MapScreen only knows about
  // the caller's own birds via GET /birds, so this alone can't include delivered mail.
  // Ignored for friend nests.
  final List<Bird> residentBirds;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final BirdService birdService;
  final ProfileService profileService;

  NestDetailsSheet({
    super.key,
    required this.username,
    required this.isOwn,
    required this.profilePictureUrl,
    required this.waypointId,
    required this.waypointName,
    required this.latitude,
    required this.longitude,
    required this.authState,
    required this.ringColor,
    this.residentBirds = const [],
    WaypointService? waypointService,
    FriendsService? friendsService,
    BirdService? birdService,
    ProfileService? profileService,
  })  : waypointService = waypointService ?? WaypointService(),
        friendsService = friendsService ?? FriendsService(),
        birdService = birdService ?? BirdService(),
        profileService = profileService ?? ProfileService();

  static Future<void> show(
    BuildContext context, {
    required String username,
    required bool isOwn,
    required String? profilePictureUrl,
    required String waypointId,
    required String waypointName,
    required double latitude,
    required double longitude,
    required AuthState authState,
    required Color ringColor,
    List<Bird> residentBirds = const [],
    WaypointService? waypointService,
    FriendsService? friendsService,
    BirdService? birdService,
    ProfileService? profileService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NestDetailsSheet(
        username: username,
        isOwn: isOwn,
        profilePictureUrl: profilePictureUrl,
        waypointId: waypointId,
        waypointName: waypointName,
        latitude: latitude,
        longitude: longitude,
        authState: authState,
        ringColor: ringColor,
        residentBirds: residentBirds,
        waypointService: waypointService,
        friendsService: friendsService,
        birdService: birdService,
        profileService: profileService,
      ),
    );
  }

  @override
  State<NestDetailsSheet> createState() => _NestDetailsSheetState();
}

class _NestDetailsSheetState extends State<NestDetailsSheet> {
  late String _name = widget.waypointName;
  late String? _pictureUrl = widget.profilePictureUrl;
  late List<Bird> _birds = widget.residentBirds;
  bool _isUploadingPicture = false;
  String? _currentUserId;

  List<Bird> get _ownIdleBirds => _birds.where((b) => b.userId == _currentUserId).toList();
  List<Bird> get _deliveredBirds => _birds.where((b) => b.userId != _currentUserId).toList();

  @override
  void initState() {
    super.initState();
    if (widget.isOwn) {
      _currentUserId = jwtSubject(widget.authState.token!);
      _loadResidents();
    }
  }

  // MapScreen's residentBirds only ever has the caller's own birds (from GET /birds), so a
  // friend's delivered bird never shows up until this sheet fetches the real resident list
  // itself via GET /waypoints/{id}/birds, which is cross-partition and includes every
  // sender. Silently keeps whatever residentBirds already had on a failed refresh - a stale
  // "Birds here" list beats blocking the whole sheet open on this fetch.
  Future<void> _loadResidents() async {
    try {
      final residents = await widget.birdService.getNestResidents(widget.authState.token!, widget.waypointId);
      if (!mounted) return;
      setState(() => _birds = residents);
    } catch (_) {
      // See comment above - not worth surfacing.
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
    // Refreshes the unread dot - the sheet above already called markBirdRead.
    setState(() => _birds = _birds.map((b) => b.id == bird.id ? _asRead(b) : b).toList());
  }

  Bird _asRead(Bird bird) => Bird(
        id: bird.id,
        userId: bird.userId,
        name: bird.name,
        currentNestId: bird.currentNestId,
        isTraveling: bird.isTraveling,
        nestFromId: bird.nestFromId,
        nestToId: bird.nestToId,
        speed: bird.speed,
        content: bird.content,
        type: bird.type,
        departedAt: bird.departedAt,
        estimatedArrivalAt: bird.estimatedArrivalAt,
        isRead: true,
        audioUrl: bird.audioUrl,
        imageUrl: bird.imageUrl,
        profilePictureUrl: bird.profilePictureUrl,
        isPublic: bird.isPublic,
      );

  Future<void> _renameNest() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(initialName: _name),
    );
    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    try {
      await widget.waypointService.updateWaypoint(
        widget.authState.token!,
        widget.waypointId,
        name: newName.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() => _name = newName.trim());
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _pickAndUploadPicture() async {
    final (List<int> bytes, String filename, String contentType) picked;
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) {
        return;
      }
      picked = (await xFile.readAsBytes(), xFile.name, xFile.mimeType ?? 'image/jpeg');
    } catch (e) {
      _showToast(e.toString(), isError: true);
      return;
    }

    setState(() => _isUploadingPicture = true);
    try {
      final url = await widget.waypointService.uploadWaypointPicture(
        widget.authState.token!,
        widget.waypointId,
        picked.$1,
        filename: picked.$2,
        contentType: picked.$3,
      );
      if (!mounted) return;
      setState(() => _pictureUrl = url);
      _showToast('Nest picture updated');
    } catch (e) {
      _showToast(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPicture = false);
      }
    }
  }

  // Every bird in widget.residentBirds is already the caller's own and idle (parked here,
  // not traveling) - there's nothing to "read", only somewhere new to send it.
  Future<void> _openSendFlow(Bird bird) async {
    final token = widget.authState.token!;
    try {
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
      ]);
      final ownNests = results[0].where((w) => w.id != widget.waypointId);
      final friendNests = results[1];

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
      setState(() => _birds = _birds.where((b) => b.id != bird.id).toList());
      _showToast('${bird.name} is on its way!');
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
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
    return Container(
      key: const Key('nestDetailsSheet'),
      decoration: const BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        // rgba(43,47,51,0.18) per the sheet-shadow token.
        boxShadow: [BoxShadow(color: Color(0x2E2B2F33), blurRadius: 30, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  // rgba(43,47,51,0.15) drag-handle token.
                  color: const Color(0x262B2F33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    key: const Key('nestPictureButton'),
                    onTap: widget.isOwn && !_isUploadingPicture ? _pickAndUploadPicture : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AvatarWithFallback(
                          avatarKey: const Key('nestDetailsAvatar'),
                          imageUrl: _pictureUrl,
                          initialsSource: widget.username,
                          radius: 26,
                          hasBorder: true,
                          borderColor: widget.ringColor,
                        ),
                        if (_isUploadingPicture) const CircularProgressIndicator(),
                        if (widget.isOwn && !_isUploadingPicture)
                          const Positioned(bottom: 0, right: 0, child: Icon(Icons.camera_alt, size: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isOwn ? 'Your nest' : "${widget.username}'s nest",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _name,
                                key: const Key('nestDetailsWaypointName'),
                                style: const TextStyle(fontSize: 13, color: CroColors.fog),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isOwn) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                key: const Key('renameNestButton'),
                                onTap: _renameNest,
                                child: const Text(
                                  'Rename',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: CroColors.deepWaypoint,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '(${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)})',
                          key: const Key('nestDetailsCoordinates'),
                          style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.isOwn) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                if (_deliveredBirds.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Delivered to you', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 8),
                  _buildDeliveredSection(),
                  const SizedBox(height: 16),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Birds here', style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                _buildBirdsSection(),
              ],
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirdsSection() {
    if (_ownIdleBirds.isEmpty) {
      return const Text('This nest is empty', key: Key('noBirdsAtNestMessage'));
    }

    return SizedBox(
      width: double.maxFinite,
      height: 160,
      child: ListView(
        children: [
          for (final bird in _ownIdleBirds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: Key('birdTile_${bird.id}'),
                onTap: () => _openSendFlow(bird),
                child: Container(
                  decoration: BoxDecoration(color: CroColors.background, borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: CroColors.waypointBlue, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bird.name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CroColors.ink),
                            ),
                            Text(bird.type, style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeliveredSection() {
    return SizedBox(
      width: double.maxFinite,
      height: 160,
      child: ListView(
        children: [
          for (final bird in _deliveredBirds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: Key('deliveredBirdTile_${bird.id}'),
                onTap: () => _openReceivedBird(bird),
                child: Container(
                  decoration: BoxDecoration(color: CroColors.background, borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: bird.isRead ? CroColors.fog : Theme.of(context).colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bird.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: bird.isRead ? FontWeight.w600 : FontWeight.w700,
                                color: CroColors.ink,
                              ),
                            ),
                            Text(
                              bird.isRead ? bird.type : 'New · ${bird.type}',
                              key: Key('deliveredBirdSubtitle_${bird.id}'),
                              style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
