import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import 'avatar_with_fallback.dart';
import 'send_bird_dialog.dart';
import 'waypoint_name_dialog.dart';

// Shared popup shown when tapping either one of the user's own nest markers or a friend's
// nest marker on the map: bordered profile picture, "Your nest" (for the user's own marker)
// or "{username}'s nest" (for a friend's) title, the name the owner gave that nest, and
// lat/long formatted to 4 decimal places - same shape for both, so a friend's nest never
// looks meaningfully different from your own. Own nests additionally get an editable
// name/picture (tap either to change them) and a "Birds here" section listing the caller's
// own idle birds currently parked at that nest - never a friend's nest inbox, and never
// birds sent by anyone but the caller.
class NestDetailsDialog extends StatefulWidget {
  final String username;
  final bool isOwn;
  final String? profilePictureUrl;
  final String waypointId;
  final String waypointName;
  final double latitude;
  final double longitude;
  final AuthState authState;
  // The caller's own idle birds already parked at this nest (MapScreen already has this
  // loaded via GET /birds - passing it in avoids a second fetch). Ignored for friend nests.
  final List<Bird> residentBirds;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final BirdService birdService;
  final ProfileService profileService;

  NestDetailsDialog({
    super.key,
    required this.username,
    required this.isOwn,
    required this.profilePictureUrl,
    required this.waypointId,
    required this.waypointName,
    required this.latitude,
    required this.longitude,
    required this.authState,
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
    List<Bird> residentBirds = const [],
    WaypointService? waypointService,
    FriendsService? friendsService,
    BirdService? birdService,
    ProfileService? profileService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => NestDetailsDialog(
        username: username,
        isOwn: isOwn,
        profilePictureUrl: profilePictureUrl,
        waypointId: waypointId,
        waypointName: waypointName,
        latitude: latitude,
        longitude: longitude,
        authState: authState,
        residentBirds: residentBirds,
        waypointService: waypointService,
        friendsService: friendsService,
        birdService: birdService,
        profileService: profileService,
      ),
    );
  }

  @override
  State<NestDetailsDialog> createState() => _NestDetailsDialogState();
}

class _NestDetailsDialogState extends State<NestDetailsDialog> {
  late String _name = widget.waypointName;
  late String? _pictureUrl = widget.profilePictureUrl;
  late List<Bird> _birds = widget.residentBirds;
  bool _isUploadingPicture = false;

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
    return AlertDialog(
      key: const Key('nestDetailsDialog'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    radius: 32,
                    hasBorder: true,
                  ),
                  if (_isUploadingPicture) const CircularProgressIndicator(),
                  if (widget.isOwn && !_isUploadingPicture)
                    const Positioned(bottom: 0, right: 0, child: Icon(Icons.camera_alt, size: 16)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.isOwn ? 'Your nest' : "${widget.username}'s nest",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_name, key: const Key('nestDetailsWaypointName'), style: Theme.of(context).textTheme.bodyMedium),
                if (widget.isOwn)
                  IconButton(
                    key: const Key('renameNestButton'),
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Rename nest',
                    onPressed: _renameNest,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '(${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)})',
              key: const Key('nestDetailsCoordinates'),
            ),
            if (widget.isOwn) ...[
              const SizedBox(height: 16),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Birds here', style: Theme.of(context).textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              _buildBirdsSection(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildBirdsSection() {
    if (_birds.isEmpty) {
      return const Text('This nest is empty', key: Key('noBirdsAtNestMessage'));
    }

    return SizedBox(
      width: double.maxFinite,
      height: 160,
      child: ListView(
        children: [
          for (final bird in _birds)
            ListTile(
              key: Key('birdTile_${bird.id}'),
              title: Text(bird.name),
              subtitle: Text(bird.type),
              onTap: () => _openSendFlow(bird),
            ),
        ],
      ),
    );
  }
}
