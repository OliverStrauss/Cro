import 'package:flutter/material.dart';

import '../screens/hub_board_screen.dart';
import '../services/hub_service.dart';
import '../services/profile_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/avatar_with_fallback.dart';

// Bottom sheet shown when tapping a Hub marker on the map - a Hub has no rename/delete
// action, unlike NestDetailsSheet's own-nest branch (nobody owns a Hub), but any signed-in
// user can tap the avatar to suggest a photo for it, subject to admin approval (see
// HubService.suggestHubPicture) - so the picture itself doesn't change here immediately.
// "View Board" is the one navigation action, pushing the full-screen message board rather
// than cramming a scrollable list into this small sheet.
class HubDetailsSheet extends StatefulWidget {
  final String id;
  final String name;
  final String? category;
  final String? profilePictureUrl;
  final double latitude;
  final double longitude;
  final AuthState authState;
  final HubService hubService;
  final ProfileService profileService;

  HubDetailsSheet({
    super.key,
    required this.id,
    required this.name,
    this.category,
    this.profilePictureUrl,
    required this.latitude,
    required this.longitude,
    required this.authState,
    HubService? hubService,
    ProfileService? profileService,
  })  : hubService = hubService ?? HubService(),
        profileService = profileService ?? ProfileService();

  static Future<void> show(
    BuildContext context, {
    required String id,
    required String name,
    String? category,
    String? profilePictureUrl,
    required double latitude,
    required double longitude,
    required AuthState authState,
    HubService? hubService,
    ProfileService? profileService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HubDetailsSheet(
        id: id,
        name: name,
        category: category,
        profilePictureUrl: profilePictureUrl,
        latitude: latitude,
        longitude: longitude,
        authState: authState,
        hubService: hubService,
        profileService: profileService,
      ),
    );
  }

  @override
  State<HubDetailsSheet> createState() => _HubDetailsSheetState();
}

class _HubDetailsSheetState extends State<HubDetailsSheet> {
  bool _isUploadingPicture = false;

  Future<void> _pickAndSuggestPicture() async {
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
      await widget.hubService.suggestHubPicture(
        widget.authState.token!,
        widget.id,
        picked.$1,
        filename: picked.$2,
        contentType: picked.$3,
      );
      _showToast('Photo suggestion submitted for review');
    } catch (e) {
      _showToast(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPicture = false);
      }
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
      key: const Key('hubDetailsSheet'),
      decoration: const BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E2B2F33),
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0x262B2F33),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  key: const Key('hubPictureButton'),
                  onTap: _isUploadingPicture ? null : _pickAndSuggestPicture,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AvatarWithFallback(
                        avatarKey: const Key('hubDetailsAvatar'),
                        imageUrl: widget.profilePictureUrl,
                        initialsSource: widget.name,
                        radius: 26,
                        hasBorder: true,
                        borderColor: Theme.of(context).colorScheme.tertiary,
                      ),
                      if (_isUploadingPicture) const CircularProgressIndicator(),
                      if (!_isUploadingPicture)
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
                        widget.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: CroColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.category ?? 'Hub',
                        key: const Key('hubDetailsCategory'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: CroColors.fog,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Location', style: TextStyle(fontSize: 13, color: CroColors.fog)),
                const Spacer(),
                Text(
                  '(${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)})',
                  key: const Key('hubDetailsLocation'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CroColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('viewHubBoardButton'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HubBoardScreen(
                      authState: widget.authState,
                      hubId: widget.id,
                      hubName: widget.name,
                    ),
                  ),
                ),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('View Board'),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CroColors.deepWaypoint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
