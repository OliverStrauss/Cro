import 'package:flutter/material.dart';

import '../../models/friend.dart';
import '../../models/friend_request.dart';
import '../../models/hub.dart';
import '../../models/hub_category.dart';
import '../../models/hub_message.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../services/profile_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../../widgets/hub_message_card.dart';

/// The hub detail panel body - header plus the hub's message board embedded directly,
/// rather than a full-screen push (see 01_web_shell_and_dock.md and the PR notes): every
/// other selection (nest, bird) already swaps the same right-hand panel, so a one-off push
/// for Hubs would break that "one screen, panel swaps" pattern. Adapted from the phone
/// app's HubBoardScreen (same load/exclusion-set logic), minus its Scaffold/AppBar chrome.
class HubPanelContent extends StatefulWidget {
  final Hub hub;
  final AuthState authState;
  final VoidCallback onClose;
  final HubService hubService;
  final FriendsService friendsService;
  final ProfileService profileService;

  const HubPanelContent({
    super.key,
    required this.hub,
    required this.authState,
    required this.onClose,
    required this.hubService,
    required this.friendsService,
    required this.profileService,
  });

  @override
  State<HubPanelContent> createState() => _HubPanelContentState();
}

class _HubPanelContentState extends State<HubPanelContent> {
  List<HubMessage> _messages = [];
  Set<String> _excludedSenderIds = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUploadingPicture = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HubPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hub.id != widget.hub.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.hubService.listMessages(token, widget.hub.id),
        widget.friendsService.getFriends(token),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
      ]);
      final messages = results[0] as List<HubMessage>;
      final friends = results[1] as List<Friend>;
      final incoming = results[2] as List<FriendRequest>;
      final outgoing = results[3] as List<FriendRequest>;

      final selfId = jwtSubject(token);
      final excluded = <String>{
        ?selfId,
        ...friends.map((f) => f.userId),
        ...incoming.map((r) => r.userId),
        ...outgoing.map((r) => r.userId),
      };

      if (!mounted) return;
      setState(() {
        _messages = messages;
        _excludedSenderIds = excluded;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // Suggestions don't auto-apply to hub.profilePictureUrl - they just sit Pending until an
  // admin approves via HubSuggestionsPanel, so there's nothing to refresh here immediately.
  Future<void> _suggestPicture() async {
    final (List<int> bytes, String filename, String contentType) picked;
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) return;
      picked = (await xFile.readAsBytes(), xFile.name, xFile.mimeType ?? 'image/jpeg');
    } catch (e) {
      _toast(e.toString(), isError: true);
      return;
    }

    setState(() => _isUploadingPicture = true);
    try {
      await widget.hubService.suggestHubPicture(
        widget.authState.token!,
        widget.hub.id,
        picked.$1,
        filename: picked.$2,
        contentType: picked.$3,
      );
      _toast('Photo suggested — pending admin approval');
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingPicture = false);
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
    final hub = widget.hub;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Tooltip(
                  message: 'Close',
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const Key('webPanelClose'),
                      customBorder: const CircleBorder(),
                      onTap: widget.onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 20, color: CroColors.fog),
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Suggest a photo',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('webSuggestHubPictureButton'),
                    customBorder: const CircleBorder(),
                    onTap: _isUploadingPicture ? null : _suggestPicture,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AvatarWithFallback(
                          imageUrl: hub.profilePictureUrl,
                          initialsSource: hub.name,
                          fallbackIcon: HubCategory.iconFor(hub.category),
                          radius: 32,
                          hasBorder: true,
                          borderColor: CroColors.deliveryAmber,
                        ),
                        if (_isUploadingPicture) const CircularProgressIndicator(),
                        if (!_isUploadingPicture)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: CroColors.deepWaypoint, shape: BoxShape.circle),
                              child: const Icon(Icons.photo_camera, size: 14, color: CroColors.surface),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(hub.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                '${hub.category ?? 'Landmark'} · anyone can send here',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: CroColors.fog),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            '(${hub.latitude.toStringAsFixed(4)}, ${hub.longitude.toStringAsFixed(4)})',
            style: const TextStyle(fontSize: 11.5, color: CroColors.fog),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: Text('The board', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Flexible(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(key: Key('hubPanelLoading'), child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('hubPanelError'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        key: Key('hubPanelEmpty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No messages here yet - be the first to send a bird this way', textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const Key('hubPanelMessageList'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        itemCount: _messages.length,
        itemBuilder: (context, i) {
          final message = _messages[i];
          return HubMessageCard(
            message: message,
            showAddFriend: !_excludedSenderIds.contains(message.senderId),
            token: widget.authState.token!,
            friendsService: widget.friendsService,
          );
        },
      ),
    );
  }
}
