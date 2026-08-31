import 'package:flutter/material.dart';

import '../../services/profile_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../models/event.dart';

/// The You screen: profile card (avatar upload, admin badge), flock stat tiles, and a
/// settings list.
class WebYouScreen extends StatefulWidget {
  final AuthState authState;
  final ProfileService profileService;
  final String username;
  final String? profilePictureUrl;
  final bool isAdmin;
  final int birdCount;
  final int nestCount;
  final int friendCount;
  final List<AppEvent> events;
  final VoidCallback onDataChanged;
  final VoidCallback onNavigateFriends;
  final VoidCallback onNavigateHubs;

  const WebYouScreen({
    super.key,
    required this.authState,
    required this.profileService,
    required this.username,
    required this.profilePictureUrl,
    required this.isAdmin,
    required this.birdCount,
    required this.nestCount,
    required this.friendCount,
    required this.events,
    required this.onDataChanged,
    required this.onNavigateFriends,
    required this.onNavigateHubs,
  });

  @override
  State<WebYouScreen> createState() => _WebYouScreenState();
}

class _WebYouScreenState extends State<WebYouScreen> {
  bool _isUploading = false;

  int get _flightsLogged => widget.events.where((e) => e.kind == EventKind.birdDeparted).length;

  Future<void> _changePicture() async {
    final (List<int> bytes, String filename, String contentType) picked;
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) return;
      picked = (await xFile.readAsBytes(), xFile.name, xFile.mimeType ?? 'image/jpeg');
    } catch (e) {
      _toast(e.toString(), isError: true);
      return;
    }

    setState(() => _isUploading = true);
    try {
      await widget.profileService.uploadProfilePicture(widget.authState.token!, picked.$1, filename: picked.$2, contentType: picked.$3);
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
    return SingleChildScrollView(
      key: const Key('webYouScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [
                BoxShadow(color: Color(0x122B2F33), blurRadius: 3, offset: Offset(0, 1)),
              ]),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    key: const Key('webChangePictureButton'),
                    onTap: _isUploading ? null : _changePicture,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AvatarWithFallback(
                          imageUrl: widget.profilePictureUrl,
                          initialsSource: widget.username,
                          radius: 42,
                          hasBorder: true,
                          borderColor: CroColors.waypointBlue,
                        ),
                        if (_isUploading) const CircularProgressIndicator(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.username, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        const Text('Click your picture to change it', style: TextStyle(fontSize: 12.5, color: CroColors.fog)),
                        if (widget.isAdmin) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: CroColors.deliveryAmber.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Admin', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: CroColors.amberInk)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _statTile('${widget.birdCount}', 'birds in your flock'),
                _statTile('${widget.nestCount}', 'nests you keep'),
                _statTile('$_flightsLogged', 'flights logged'),
                _statTile('${widget.friendCount}', 'friends'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
                BoxShadow(color: Color(0x0F2B2F33), blurRadius: 3, offset: Offset(0, 1)),
              ]),
              child: Column(
                children: [
                  _settingsRow(
                    key: 'webSettingsBlockedUsers',
                    label: 'Blocked users',
                    detail: 'Manage from the Friends screen',
                    onTap: widget.onNavigateFriends,
                  ),
                  _settingsRow(
                    key: 'webSettingsHubSuggestions',
                    label: 'Hub suggestions',
                    detail: 'Manage from the Hubs screen',
                    onTap: widget.onNavigateHubs,
                  ),
                  _settingsRow(
                    key: 'webSettingsChangePicture',
                    label: 'Change profile picture',
                    detail: 'JPG or PNG',
                    onTap: _isUploading ? null : _changePicture,
                  ),
                  _settingsRow(
                    key: 'webSettingsSignOut',
                    label: 'Sign out',
                    detail: 'You will need your password again',
                    color: CroColors.alertAway,
                    onTap: widget.authState.logout,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [
        BoxShadow(color: Color(0x0F2B2F33), blurRadius: 3, offset: Offset(0, 1)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
        ],
      ),
    );
  }

  Widget _settingsRow({
    required String key,
    required String label,
    required String detail,
    required VoidCallback? onTap,
    Color color = CroColors.ink,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        InkWell(
          key: Key(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: color)),
                      const SizedBox(height: 2),
                      Text(detail, style: const TextStyle(fontSize: 11.5, color: CroColors.fog)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: CroColors.fog),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, color: CroColors.ink.withValues(alpha: 0.06)),
      ],
    );
  }
}
