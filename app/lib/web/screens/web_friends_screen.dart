import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/blocked_user.dart';
import '../../models/friend.dart';
import '../../models/friend_request.dart';
import '../../models/user_search_result.dart';
import '../../models/waypoint.dart';
import '../../services/friends_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../widgets/avatar_with_fallback.dart';

/// The Friends screen: friend cards (auto-assigned trail color, no picker - see the web
/// redesign's README on this divergence), a live username search excluding people already
/// in some relationship with the caller, incoming/outgoing requests, and blocked users.
class WebFriendsScreen extends StatefulWidget {
  final AuthState authState;
  final FriendsService friendsService;
  final List<Waypoint> friendWaypoints;
  final bool isAdmin;
  // Called after any action that changes the friends graph (accept/decline/remove/block)
  // so the shell can refresh the rail's incoming-invite badge to match.
  final VoidCallback onDataChanged;

  const WebFriendsScreen({
    super.key,
    required this.authState,
    required this.friendsService,
    required this.friendWaypoints,
    required this.isAdmin,
    required this.onDataChanged,
  });

  @override
  State<WebFriendsScreen> createState() => _WebFriendsScreenState();
}

class _WebFriendsScreenState extends State<WebFriendsScreen> {
  List<Friend> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];
  List<BlockedUser> _blocked = [];
  bool _isLoading = true;
  String? _errorMessage;

  final _searchController = TextEditingController();
  List<UserSearchResult> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
      return const Center(key: Key('webFriendsLoading'), child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('webFriendsError'),
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
      key: const Key('webFriendsScreen'),
      // Top padding keeps content clear of the floating actions cluster (no top bar - see
      // 05_web_ui_updates.md item 1).
      padding: const EdgeInsets.fromLTRB(26, 74, 26, 240),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('Your friends', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                const Text('Trail colors are assigned automatically', style: TextStyle(fontSize: 12, color: CroColors.fog)),
              ],
            ),
            const SizedBox(height: 12),
            if (_friends.isEmpty)
              const Text('No friends yet', key: Key('noFriendsMessage'), style: TextStyle(fontSize: 12.5, color: CroColors.fog))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final friend in _friends) _friendCard(friend)],
              ),
            const SizedBox(height: 26),
            const Text('Find people', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
              const Text('Invites for you', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [for (final r in _incoming) _inviteCard(r)]),
            ],
            if (_outgoing.isNotEmpty) ...[
              const SizedBox(height: 26),
              const Text('Waiting on them', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(width: 420, child: Column(children: [for (final r in _outgoing) _outgoingRow(r)])),
            ],
            const SizedBox(height: 26),
            const Text('Blocked', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_blocked.isEmpty)
              const Text('No blocked users', style: TextStyle(fontSize: 12.5, color: CroColors.fog))
            else
              SizedBox(width: 420, child: Column(children: [for (final b in _blocked) _blockedRow(b)])),
          ],
        ),
      ),
    );
  }

  Widget _friendCard(Friend friend) {
    final color = hexToColor(friend.color ?? '#6B7280');
    final nestCount = _nestCountFor(friend.username);
    return Container(
      key: Key('webFriendCard_${friend.userId}'),
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x122B2F33), blurRadius: 3, offset: Offset(0, 1)),
      ]),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarWithFallback(imageUrl: friend.profilePictureUrl, initialsSource: friend.username, radius: 26, hasBorder: true, borderColor: color),
              const SizedBox(height: 8),
              Text(friend.username, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
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
                      style: const TextStyle(fontSize: 11, color: CroColors.fog),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              key: Key('webRemoveFriendButton_${friend.userId}'),
              onTap: () => _removeFriend(friend.userId),
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: CroColors.ink.withValues(alpha: 0.15))),
                child: const Text('×', style: TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w700, color: CroColors.fog)),
              ),
            ),
          ),
          if (widget.isAdmin && !friend.isAdmin)
            Positioned(
              bottom: -4,
              right: -4,
              child: GestureDetector(
                key: Key('webMakeAdminButton_${friend.userId}'),
                onTap: () => _confirmMakeAdmin(friend),
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: CroColors.ink.withValues(alpha: 0.15))),
                  child: const Icon(Icons.shield_outlined, size: 12, color: CroColors.deepWaypoint),
                ),
              ),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [
        BoxShadow(color: Color(0x1F2B2F33), blurRadius: 14, offset: Offset(0, 4)),
      ]),
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
                  Expanded(child: Text(r.username, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
                  GestureDetector(
                    key: Key('webSendRequestButton_${r.userId}'),
                    onTap: () => _sendRequest(r.username),
                    child: const Text('Send request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    key: Key('webBlockSearchButton_${r.userId}'),
                    onTap: () => _blockFromSearch(r.userId),
                    child: const Text('Block', style: TextStyle(fontSize: 12, color: CroColors.fog)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x122B2F33), blurRadius: 3, offset: Offset(0, 1)),
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWithFallback(imageUrl: request.profilePictureUrl, initialsSource: request.username, radius: 23),
          const SizedBox(height: 8),
          Text(request.username, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                key: Key('webAcceptInviteButton_${request.userId}'),
                onTap: () => _accept(request.userId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(color: CroColors.waypointBlue, borderRadius: BorderRadius.circular(9)),
                  child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: Key('webDeclineInviteButton_${request.userId}'),
                onTap: () => _decline(request.userId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: CroColors.ink.withValues(alpha: 0.15))),
                  child: const Text('Decline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.fog)),
                ),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: Text(request.username, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
          const Text('Waiting', style: TextStyle(fontSize: 11.5, color: CroColors.fog)),
          const SizedBox(width: 10),
          GestureDetector(
            key: Key('webCancelOutgoingButton_${request.userId}'),
            onTap: () => _cancelOutgoing(request.userId),
            child: const Text('×', style: TextStyle(fontSize: 14, color: CroColors.fog)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: Text(user.username, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: CroColors.fog))),
          GestureDetector(
            key: Key('webUnblockButton_${user.userId}'),
            onTap: () => _unblock(user.userId),
            child: const Text('Unblock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CroColors.deepWaypoint)),
          ),
        ],
      ),
    );
  }
}
