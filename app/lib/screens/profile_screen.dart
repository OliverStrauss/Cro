import 'dart:async';

import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_request.dart';
import '../models/user_profile.dart';
import '../models/user_search_result.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../utils/jwt_utils.dart';
import '../widgets/avatar_with_fallback.dart';
import '../widgets/friend_list_tile.dart';
import '../widgets/invite_card.dart';

// Combined social screen: profile picture, friends, add-by-username search, and pending
// invites all in one place, rather than splitting friends off into their own tab.
class ProfileScreen extends StatefulWidget {
  final AuthState authState;
  final ProfileService profileService;
  final FriendsService friendsService;

  ProfileScreen({
    super.key,
    required this.authState,
    ProfileService? profileService,
    FriendsService? friendsService,
  }) : profileService = profileService ?? ProfileService(),
       friendsService = friendsService ?? FriendsService();

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<Friend> _friends = [];
  List<FriendRequest> _incomingRequests = [];
  List<FriendRequest> _outgoingRequests = [];

  bool _isLoading = true;
  String? _errorMessage;
  bool _isUploading = false;

  final _usernameController = TextEditingController();
  bool _isSendingRequest = false;

  // Live "as you type" suggestions for the Add Friends field - debounced so every
  // keystroke doesn't fire its own search request.
  List<UserSearchResult> _suggestions = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _usernameController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final userId = jwtSubject(token);
      if (userId == null) {
        throw ProfileException('Could not determine the current user');
      }
      final results = await Future.wait([
        widget.profileService.getUser(userId),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
        widget.friendsService.getFriends(token),
      ]);
      setState(() {
        _profile = results[0] as UserProfile;
        _incomingRequests = results[1] as List<FriendRequest>;
        _outgoingRequests = results[2] as List<FriendRequest>;
        _friends = results[3] as List<Friend>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadPicture() async {
    final (List<int> bytes, String filename, String contentType) picked;
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) {
        return;
      }
      picked = (
        await xFile.readAsBytes(),
        xFile.name,
        xFile.mimeType ?? 'image/jpeg',
      );
    } catch (e) {
      _showToast(e.toString(), isError: true);
      return;
    }

    setState(() => _isUploading = true);
    try {
      await widget.profileService.uploadProfilePicture(
        widget.authState.token!,
        picked.$1,
        filename: picked.$2,
        contentType: picked.$3,
      );
      _showToast('Profile picture updated');
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _onSearchTextChanged() {
    final query = _usernameController.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSuggestionSearch(query),
    );
  }

  Future<void> _runSuggestionSearch(String query) async {
    try {
      final results = await widget.friendsService.searchUsers(
        widget.authState.token!,
        query,
      );
      if (!mounted) return;
      // Already a friend, or already a pending request either direction - nothing useful
      // to suggest adding again.
      final excludedUsernames = <String>{
        ..._friends.map((f) => f.username.toLowerCase()),
        ..._incomingRequests.map((r) => r.username.toLowerCase()),
        ..._outgoingRequests.map((r) => r.username.toLowerCase()),
      };
      setState(() {
        _suggestions = results
            .where((r) => !excludedUsernames.contains(r.username.toLowerCase()))
            .take(5)
            .toList();
      });
    } catch (_) {
      // A blip on a live-as-you-type search shouldn't surface a toast/error state - the
      // submit-on-Enter/send-icon path below still works regardless.
    }
  }

  Future<void> _sendFriendRequest() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      return;
    }
    await _sendRequestFor(username);
  }

  Future<void> _addSuggestedFriend(UserSearchResult result) =>
      _sendRequestFor(result.username);

  Future<void> _sendRequestFor(String username) async {
    setState(() => _isSendingRequest = true);

    try {
      await widget.friendsService.sendFriendRequest(
        widget.authState.token!,
        username,
      );
      _usernameController.clear();
      setState(() => _suggestions = []);
      _showToast('Friend request sent to $username');
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSendingRequest = false);
      }
    }
  }

  Future<void> _acceptRequest(String requesterId) async {
    try {
      await widget.friendsService.acceptFriendRequest(
        widget.authState.token!,
        requesterId,
      );
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _declineRequest(String requesterId) async {
    try {
      await widget.friendsService.removeFriend(
        widget.authState.token!,
        requesterId,
      );
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _cancelRequest(String targetId) async {
    try {
      await widget.friendsService.removeFriend(
        widget.authState.token!,
        targetId,
      );
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _removeFriend(String friendId) async {
    try {
      await widget.friendsService.removeFriend(
        widget.authState.token!,
        friendId,
      );
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _setFriendColor(String friendId, String color) async {
    try {
      await widget.friendsService.setFriendColor(
        widget.authState.token!,
        friendId,
        color,
      );
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  // "Toast" here is a SnackBar - Flutter has no separate toast widget, and SnackBar is
  // the platform-idiomatic equivalent (brief, dismissible, doesn't block interaction).
  void _showToast(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          // Kept outside the loading/error states below - signing out shouldn't depend
          // on the profile/friends fetch having succeeded.
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('logoutButton'),
                onPressed: widget.authState.logout,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: CroColors.ink.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  foregroundColor: CroColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: Key('profileLoadingIndicator'),
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('profileErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadAll, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: _buildAvatarSection()),
        const SizedBox(height: 24),
        Text('Your Friends', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildFriendsRow(),
        const SizedBox(height: 24),
        Text(
          'Search For Friends',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildSearchField(),
        if (_incomingRequests.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Pending Friend Invites',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildInvitesRow(),
        ],
        if (_outgoingRequests.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            key: const Key('outgoingRequestsSection'),
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pending', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final request in _outgoingRequests)
                  Container(
                    key: Key('outgoingRequest_${request.userId}'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: CroColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            request.username,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CroColors.ink,
                            ),
                          ),
                        ),
                        const Text(
                          'Waiting',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: CroColors.fog,
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          key: Key('cancelRequestButton_${request.userId}'),
                          onTap: () => _cancelRequest(request.userId),
                          child: const Text(
                            '×',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: CroColors.fog,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatarSection() {
    final profile = _profile!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const Key('profileAvatarButton'),
          onTap: _isUploading ? null : _pickAndUploadPicture,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AvatarWithFallback(
                imageUrl: profile.profilePictureUrl,
                initialsSource: profile.username,
                radius: 42,
                hasBorder: true,
                borderColor: CroColors.waypointBlue,
              ),
              if (_isUploading) const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap to change picture',
          style: TextStyle(fontSize: 11.5, color: CroColors.fog),
        ),
        const SizedBox(height: 16),
        Text(
          profile.username,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: CroColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildFriendsRow() {
    if (_friends.isEmpty) {
      return const Center(
        key: Key('noFriendsMessage'),
        child: Text(
          'No friends yet',
          style: TextStyle(fontSize: 13, color: CroColors.fog),
        ),
      );
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _friends.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              FriendListTile(
                friend: friend,
                onColorSelected: (color) =>
                    _setFriendColor(friend.userId, color),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  key: Key('removeFriendButton_${friend.userId}'),
                  onTap: () => _removeFriend(friend.userId),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CroColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CroColors.ink.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Text(
                      '×',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: CroColors.fog,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('addFriendUsernameField'),
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _sendFriendRequest(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('sendFriendRequestButton'),
              icon: _isSendingRequest
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: _isSendingRequest ? null : _sendFriendRequest,
            ),
          ],
        ),
        if (_suggestions.isNotEmpty) _buildSuggestionsList(),
      ],
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      key: const Key('friendSuggestionsList'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: CroColors.surface,
        borderRadius: BorderRadius.circular(12),
        // rgba(43,47,51,0.12) per the floating-card-shadow token.
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F2B2F33),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final result in _suggestions)
            GestureDetector(
              key: Key('friendSuggestion_${result.userId}'),
              onTap: () => _addSuggestedFriend(result),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AvatarWithFallback(
                      avatarKey: Key('friendSuggestionAvatar_${result.userId}'),
                      imageUrl: result.profilePictureUrl,
                      initialsSource: result.username,
                      radius: 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        result.username,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CroColors.ink,
                        ),
                      ),
                    ),
                    const Text(
                      '+ Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: CroColors.waypointBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInvitesRow() {
    return SizedBox(
      key: const Key('incomingRequestsSection'),
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _incomingRequests.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final request = _incomingRequests[index];
          return InviteCard(
            userId: request.userId,
            username: request.username,
            profilePictureUrl: request.profilePictureUrl,
            onAccept: () => _acceptRequest(request.userId),
            onDecline: () => _declineRequest(request.userId),
          );
        },
      ),
    );
  }
}
