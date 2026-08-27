import 'dart:async';

import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_request.dart';
import '../models/hub_message.dart';
import '../services/friends_service.dart';
import '../services/hub_service.dart';
import '../state/auth_state.dart';
import '../utils/jwt_utils.dart';
import '../widgets/hub_message_card.dart';

// Full-screen, scrollable, chronological (newest-first, per GET /hubs/{id}/messages) board
// of everything that's landed at this Hub - pushed from HubDetailsSheet's "View Board"
// button rather than crammed into that small bottom sheet.
class HubBoardScreen extends StatefulWidget {
  final AuthState authState;
  final String hubId;
  final String hubName;
  final HubService hubService;
  final FriendsService friendsService;

  HubBoardScreen({
    super.key,
    required this.authState,
    required this.hubId,
    required this.hubName,
    HubService? hubService,
    FriendsService? friendsService,
  })  : hubService = hubService ?? HubService(),
        friendsService = friendsService ?? FriendsService();

  @override
  State<HubBoardScreen> createState() => _HubBoardScreenState();
}

class _HubBoardScreenState extends State<HubBoardScreen> {
  List<HubMessage> _messages = [];
  // Senders who shouldn't get an "Add Friend" button: the viewer themself, already-accepted
  // friends, and anyone with a pending request either direction.
  Set<String> _excludedSenderIds = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.hubService.listMessages(token, widget.hubId),
        widget.friendsService.getFriends(token),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
      ]);
      final messages = results[0] as List<HubMessage>;
      final friends = results[1] as List<Friend>;
      final incoming = results[2] as List<FriendRequest>;
      final outgoing = results[3] as List<FriendRequest>;

      final selfId = jwtSubject(token);
      final excludedSenderIds = <String>{
        ?selfId,
        ...friends.map((f) => f.userId),
        ...incoming.map((r) => r.userId),
        ...outgoing.map((r) => r.userId),
      };

      setState(() {
        _messages = messages;
        _excludedSenderIds = excludedSenderIds;
        _isLoading = false;
      });

      // Clears this hub's unread badge on the map - same "mark read on open" pattern as a
      // received bird sheet. Best-effort: a failure here shouldn't block viewing the board.
      unawaited(widget.hubService.markHubRead(token, widget.hubId));
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.hubName} Board')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('hubBoardLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('hubBoardErrorState'),
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
        key: Key('hubBoardEmptyState'),
        child: Text('No messages here yet - be the first to send a bird this way'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const Key('hubBoardList'),
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
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
