import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_request.dart';
import '../models/user_profile.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../state/auth_state.dart';
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
  })  : profileService = profileService ?? ProfileService(),
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

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
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
      picked = (await xFile.readAsBytes(), xFile.name, xFile.mimeType ?? 'image/jpeg');
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

  Future<void> _sendFriendRequest() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      return;
    }

    setState(() => _isSendingRequest = true);

    try {
      await widget.friendsService.sendFriendRequest(widget.authState.token!, username);
      _usernameController.clear();
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
      await widget.friendsService.acceptFriendRequest(widget.authState.token!, requesterId);
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _declineRequest(String requesterId) async {
    try {
      await widget.friendsService.removeFriend(widget.authState.token!, requesterId);
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _cancelRequest(String targetId) async {
    try {
      await widget.friendsService.removeFriend(widget.authState.token!, targetId);
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _removeFriend(String friendId) async {
    try {
      await widget.friendsService.removeFriend(widget.authState.token!, friendId);
      await _loadAll();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _setFriendColor(String friendId, String color) async {
    try {
      await widget.friendsService.setFriendColor(widget.authState.token!, friendId, color);
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
            child: ElevatedButton.icon(
              key: const Key('logoutButton'),
              onPressed: widget.authState.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('profileLoadingIndicator'), child: CircularProgressIndicator());
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
        Text('Friends', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildFriendsRow(),
        const SizedBox(height: 24),
        Text('Search', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildSearchField(),
        if (_incomingRequests.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Invites', style: Theme.of(context).textTheme.titleMedium),
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
                for (final request in _outgoingRequests)
                  Card(
                    key: Key('outgoingRequest_${request.userId}'),
                    child: ListTile(
                      title: Text(request.username),
                      subtitle: const Text('Waiting for them to accept'),
                      trailing: IconButton(
                        key: Key('cancelRequestButton_${request.userId}'),
                        icon: const Icon(Icons.close),
                        onPressed: () => _cancelRequest(request.userId),
                      ),
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
                radius: 48,
              ),
              if (_isUploading) const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Tap to change picture', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        Text(profile.username, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }

  Widget _buildFriendsRow() {
    if (_friends.isEmpty) {
      return const Center(key: Key('noFriendsMessage'), child: Text('No friends yet'));
    }
    return SizedBox(
      height: 110,
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
                onColorSelected: (color) => _setFriendColor(friend.userId, color),
              ),
              Positioned(
                top: -8,
                right: -8,
                child: IconButton(
                  key: Key('removeFriendButton_${friend.userId}'),
                  icon: const Icon(Icons.cancel, size: 20),
                  onPressed: () => _removeFriend(friend.userId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('addFriendUsernameField'),
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _sendFriendRequest(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('sendFriendRequestButton'),
          icon: _isSendingRequest
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          onPressed: _isSendingRequest ? null : _sendFriendRequest,
        ),
      ],
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
