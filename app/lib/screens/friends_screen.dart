import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_request.dart';
import '../services/friends_service.dart';
import '../state/auth_state.dart';
import '../widgets/friend_list_tile.dart';

class FriendsScreen extends StatefulWidget {
  final AuthState authState;
  final FriendsService friendsService;

  FriendsScreen({super.key, required this.authState, FriendsService? friendsService})
      : friendsService = friendsService ?? FriendsService();

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<FriendRequest> _incomingRequests = [];
  List<Friend> _friends = [];

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
      final incoming = await widget.friendsService.getIncomingRequests(token);
      final friends = await widget.friendsService.getFriends(token);
      setState(() {
        _incomingRequests = incoming;
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
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
      appBar: AppBar(title: const Text('Friends')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('friendsLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('friendsErrorState'),
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

    return Column(
      children: [
        if (_incomingRequests.isNotEmpty)
          Padding(
            key: const Key('incomingRequestsSection'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requests', style: Theme.of(context).textTheme.titleMedium),
                for (final request in _incomingRequests)
                  Card(
                    key: Key('incomingRequest_${request.userId}'),
                    child: ListTile(
                      title: Text(request.username),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('acceptRequestButton_${request.userId}'),
                            icon: const Icon(Icons.check),
                            onPressed: () => _acceptRequest(request.userId),
                          ),
                          IconButton(
                            key: Key('declineRequestButton_${request.userId}'),
                            icon: const Icon(Icons.close),
                            onPressed: () => _declineRequest(request.userId),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a friend', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('addFriendUsernameField'),
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
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
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _isSendingRequest ? null : _sendFriendRequest,
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _friends.isEmpty
              ? const Center(key: Key('noFriendsMessage'), child: Text('No friends yet'))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    return Row(
                      children: [
                        Expanded(
                          child: FriendListTile(
                            friend: friend,
                            onColorSelected: (color) => _setFriendColor(friend.userId, color),
                          ),
                        ),
                        IconButton(
                          key: Key('removeFriendButton_${friend.userId}'),
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _removeFriend(friend.userId),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
