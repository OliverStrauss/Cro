import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/blocked_user.dart';
import '../../models/friend.dart';
import '../../models/friend_request.dart';
import '../../models/user_search_result.dart';
import '../../models/waypoint.dart';
import '../../services/friends_service.dart';
import '../../services/profile_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../widgets/avatar_with_fallback.dart';

/// The Profile screen: a top card (avatar upload, admin badge, sign out) followed by the
/// friends view (auto-assigned trail color friend cards, live username search excluding
/// people already in some relationship with the caller, incoming/outgoing requests, and
/// blocked users) - merged from the old separate You/Friends screens, whose settings list
/// (beyond sign out) was just dead-weight navigation shortcuts to screens already reachable
/// from the icon rail.
class WebProfileScreen extends StatefulWidget {
  final AuthState authState;
  final ProfileService profileService;
  final FriendsService friendsService;
  final String username;
  final String? profilePictureUrl;
  final bool isAdmin;
  final List<Waypoint> friendWaypoints;
  final VoidCallback onDataChanged;

  const WebProfileScreen({
    super.key,
    required this.authState,
    required this.profileService,
    required this.friendsService,
    required this.username,
    required this.profilePictureUrl,
    required this.isAdmin,
    required this.friendWaypoints,
    required this.onDataChanged,
  });

  @override
  State<WebProfileScreen> createState() => _WebProfileScreenState();
}

class _WebProfileScreenState extends State<WebProfileScreen> {
  bool _isUploading = false;

  List<Friend> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];
  List<BlockedUser> _blocked = [];
  bool _isLoading = true;
  String? _errorMessage;

  final _searchController = TextEditingController();
  List<UserSearchResult> _searchResults = [];
  Timer? _searchDebounce;
  // Same "no live-update mechanism exists here yet" gap WebShellData.startPolling() closes
  // for birds/notifications - this screen fetches its own copy of friends/requests/blocked
  // independently of WebShellData, so it needs its own poll to stay live too.
  Timer? _livePoll;
  // Inline two-step "Confirm?" pattern, same as web_nests_screen.dart's delete and
  // hub_suggestions_panel.dart's reject - second tap on the same id executes.
  String? _confirmRemoveId;
  String? _confirmBlockSearchId;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
    _livePoll = Timer.periodic(const Duration(seconds: 3), (_) => _pollLive());
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

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

  // Quiet refresh for the timer above - unlike _load(), never toggles _isLoading, so a
  // background tick doesn't flash the whole screen back to a spinner. Same "a blip on a
  // silent background poll shouldn't blank an already-rendered screen" reasoning as
  // WebShellData's own poll.
  Future<void> _pollLive() async {
    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.friendsService.getFriends(token),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
        widget.friendsService.getBlockedUsers(token),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<Friend>;
        _incoming = results[1] as List<FriendRequest>;
        _outgoing = results[2] as List<FriendRequest>;
        _blocked = results[3] as List<BlockedUser>;
      });
    } catch (_) {
      // Swallow - see the comment on _livePoll's declaration above.
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.friendsService.getFriends(token),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
        widget.friendsService.getBlockedUsers(token),
      ]);
      setState(() {
        _friends = results[0] as List<Friend>;
        _incoming = results[1] as List<FriendRequest>;
        _outgoing = results[2] as List<FriendRequest>;
        _blocked = results[3] as List<BlockedUser>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      if (_searchResults.isNotEmpty) setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await widget.friendsService.searchUsers(widget.authState.token!, query);
      if (!mounted) return;
      // Client-side exclusion of everyone already in some relationship with the caller -
      // the search endpoint itself only excludes the caller.
      final excluded = <String>{
        ..._friends.map((f) => f.username.toLowerCase()),
        ..._incoming.map((r) => r.username.toLowerCase()),
        ..._outgoing.map((r) => r.username.toLowerCase()),
        ..._blocked.map((b) => b.username.toLowerCase()),
      };
      setState(() {
        _searchResults = results.where((r) => !excluded.contains(r.username.toLowerCase())).toList();
      });
    } catch (_) {
      // A blip on live-as-you-type search isn't worth surfacing.
    }
  }

  Future<void> _sendRequest(String username) async {
    try {
      await widget.friendsService.sendFriendRequest(widget.authState.token!, username);
      _searchController.clear();
      setState(() => _searchResults = []);
      await _load();
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _blockFromSearch(String userId) async {
    if (_confirmBlockSearchId != userId) {
      setState(() => _confirmBlockSearchId = userId);
      return;
    }
    setState(() => _confirmBlockSearchId = null);
    try {
      await widget.friendsService.blockUser(widget.authState.token!, userId);
      _searchController.clear();
      setState(() => _searchResults = []);
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _accept(String requesterId) async {
    try {
      await widget.friendsService.acceptFriendRequest(widget.authState.token!, requesterId);
      await _load();
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _decline(String requesterId) async {
    try {
      await widget.friendsService.declineFriendRequest(widget.authState.token!, requesterId);
      await _load();
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _cancelOutgoing(String targetId) async {
    try {
      await widget.friendsService.removeFriend(widget.authState.token!, targetId);
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _removeFriend(String friendId) async {
    if (_confirmRemoveId != friendId) {
      setState(() => _confirmRemoveId = friendId);
      return;
    }
    setState(() => _confirmRemoveId = null);
    try {
      await widget.friendsService.removeFriend(widget.authState.token!, friendId);
      await _load();
      widget.onDataChanged();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  Future<void> _unblock(String userId) async {
    try {
      await widget.friendsService.unblockUser(widget.authState.token!, userId);
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    }
  }

  // Same "are you sure" confirm dialog as the phone app's ProfileScreen - granting admin is
  // high-stakes enough to warrant an explicit confirm, unlike everything else on this screen.
  Future<void> _confirmMakeAdmin(Friend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make admin?'),
        content: Text('Make ${friend.username} an admin? Are you sure?'),
        actions: [
          TextButton(
            key: const Key('cancelMakeAdminButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmMakeAdminButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.friendsService.makeAdmin(widget.authState.token!, friend.userId);
      _toast('${friend.username} is now an admin');
      await _load();
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

  int _nestCountFor(String username) => widget.friendWaypoints.where((w) => w.username == username).length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(key: Key('webProfileLoading'), child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('webProfileError'),
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

    return SingleChildScrollView(
      key: const Key('webProfileScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileCard(),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('YOUR FRIENDS', style: CroTextStyles.label(size: 13)),
                const SizedBox(width: 10),
                Text('trail colors are assigned automatically', style: CroTextStyles.data(size: 11.5)),
              ],
            ),
            const SizedBox(height: 12),
            if (_friends.isEmpty)
              Text('No friends yet', key: const Key('noFriendsMessage'), style: CroTextStyles.data(size: 12.5))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final friend in _friends) _friendCard(friend)],
              ),
            const SizedBox(height: 26),
            Text('FIND PEOPLE', style: CroTextStyles.label(size: 13)),
            const SizedBox(height: 12),
            SizedBox(
              width: 420,
              child: TextField(
                key: const Key('webFriendSearchField'),
                controller: _searchController,
                decoration: const InputDecoration(hintText: 'Search by username', prefixIcon: Icon(Icons.search)),
              ),
            ),
            if (_searchResults.isNotEmpty) _searchResultsList(),
            if (_incoming.isNotEmpty) ...[
              const SizedBox(height: 26),
              Text('INVITES FOR YOU', style: CroTextStyles.label(size: 13)),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [for (final r in _incoming) _inviteCard(r)]),
            ],
            if (_outgoing.isNotEmpty) ...[
              const SizedBox(height: 26),
              Text('WAITING ON THEM', style: CroTextStyles.label(size: 13)),
              const SizedBox(height: 12),
              SizedBox(width: 420, child: Column(children: [for (final r in _outgoing) _outgoingRow(r)])),
            ],
            const SizedBox(height: 26),
            Text('BLOCKED', style: CroTextStyles.label(size: 13)),
            const SizedBox(height: 12),
            if (_blocked.isEmpty)
              Text('No blocked users', style: CroTextStyles.data(size: 12.5))
            else
              SizedBox(width: 420, child: Column(children: [for (final b in _blocked) _blockedRow(b)])),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Change profile picture',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const Key('webChangePictureButton'),
                customBorder: const CircleBorder(),
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
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.username, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Click your picture to change it', style: CroTextStyles.data(size: 12.5)),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(border: Border.all(color: CroColors.deliveryAmber), borderRadius: CroBorders.radiusSmall),
                    child: Text('ADMIN', style: CroTextStyles.stamp()),
                  ),
                ],
              ],
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('webSignOutButton'),
              borderRadius: CroBorders.radiusSmall,
              onTap: widget.authState.logout,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text('SIGN OUT', style: CroTextStyles.label(size: 11, color: CroColors.alertAway)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A remove (x) and, for admins, a make-admin control used to float as circular badges
  // peeking off this card's top-right/bottom-right corners (negative Positioned offsets) -
  // at the grid's 12px gap they could overlap the neighboring card's own corner badge. Both
  // now sit inline in a footer row within the card's own bounds instead, hairline-divided
  // from the identity block above - fits the ledger-row language the rest of the world uses,
  // and structurally can't overlap a neighbor.
  Widget _friendCard(Friend friend) {
    final color = hexToColor(friend.color ?? '#6B7280');
    final nestCount = _nestCountFor(friend.username);
    final isConfirmingRemove = _confirmRemoveId == friend.userId;
    return Container(
      key: Key('webFriendCard_${friend.userId}'),
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(imageUrl: friend.profilePictureUrl, initialsSource: friend.username, radius: 26, hasBorder: true, borderColor: color),
          const SizedBox(height: 8),
          Text(
            friend.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 14, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  nestCount == 1 ? '1 nest on your map' : '$nestCount nests',
                  overflow: TextOverflow.ellipsis,
                  style: CroTextStyles.data(size: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isAdmin && !friend.isAdmin) ...[
                Tooltip(
                  message: 'Make admin',
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('webMakeAdminButton_${friend.userId}'),
                      borderRadius: CroBorders.radiusSmall,
                      onTap: () => _confirmMakeAdmin(friend),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.shield_outlined, size: 15, color: CroColors.deepWaypoint),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Tooltip(
                message: isConfirmingRemove ? 'Tap again to remove' : 'Remove friend',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: Key('webRemoveFriendButton_${friend.userId}'),
                    borderRadius: CroBorders.radiusSmall,
                    onTap: () => _removeFriend(friend.userId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                      child: Text(
                        isConfirmingRemove ? 'CONFIRM?' : 'REMOVE',
                        style: CroTextStyles.label(size: 10, color: isConfirmingRemove ? Theme.of(context).colorScheme.error : CroColors.fog),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchResultsList() {
    return Container(
      key: const Key('webFriendSearchResults'),
      width: 420,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in _searchResults)
            Padding(
              key: Key('webFriendSuggestion_${r.userId}'),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              child: Row(
                children: [
                  AvatarWithFallback(imageUrl: r.profilePictureUrl, initialsSource: r.username, radius: 16),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      r.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('webSendRequestButton_${r.userId}'),
                      borderRadius: CroBorders.radiusSmall,
                      onTap: () => _sendRequest(r.username),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text('SEND REQUEST', style: CroTextStyles.label(size: 11, color: CroColors.deepWaypoint)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('webBlockSearchButton_${r.userId}'),
                      borderRadius: CroBorders.radiusSmall,
                      onTap: () => _blockFromSearch(r.userId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          _confirmBlockSearchId == r.userId ? 'CONFIRM?' : 'BLOCK',
                          style: CroTextStyles.label(size: 11, color: _confirmBlockSearchId == r.userId ? Theme.of(context).colorScheme.error : CroColors.fog),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _inviteCard(FriendRequest request) {
    return Container(
      key: Key('webInviteCard_${request.userId}'),
      width: 184,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(imageUrl: request.profilePictureUrl, initialsSource: request.username, radius: 23),
          const SizedBox(height: 8),
          Text(
            request.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                key: Key('webAcceptInviteButton_${request.userId}'),
                onPressed: () => _accept(request.userId),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), textStyle: CroTextStyles.label(size: 11, color: CroColors.surface)),
                child: const Text('ACCEPT'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: Key('webDeclineInviteButton_${request.userId}'),
                onPressed: () => _decline(request.userId),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: CroTextStyles.label(size: 11, color: CroColors.fog)),
                child: const Text('DECLINE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _outgoingRow(FriendRequest request) {
    return Container(
      key: Key('webOutgoingRow_${request.userId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: CroBorders.radiusSmall, border: Border.all(color: CroColors.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              request.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          Text('WAITING', style: CroTextStyles.label(size: 10.5, color: CroColors.fog)),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Cancel request',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: Key('webCancelOutgoingButton_${request.userId}'),
                customBorder: const CircleBorder(),
                onTap: () => _cancelOutgoing(request.userId),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Text('×', style: TextStyle(fontSize: 14, color: CroColors.fog)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockedRow(BlockedUser user) {
    return Container(
      key: Key('webBlockedRow_${user.userId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: CroBorders.radiusSmall, border: Border.all(color: CroColors.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: CroColors.fog),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('webUnblockButton_${user.userId}'),
              borderRadius: CroBorders.radiusSmall,
              onTap: () => _unblock(user.userId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text('UNBLOCK', style: CroTextStyles.label(size: 11, color: CroColors.deepWaypoint)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
