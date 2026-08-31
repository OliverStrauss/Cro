import 'package:flutter/material.dart';

import '../../models/friend.dart';
import '../../models/friend_request.dart';
import '../../models/hub.dart';
import '../../models/hub_message.dart';
import '../../services/friends_service.dart';
import '../../services/hub_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/jwt_utils.dart';
import '../../widgets/hub_message_card.dart';
import 'panel_header.dart';

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

  const HubPanelContent({
    super.key,
    required this.hub,
    required this.authState,
    required this.onClose,
    required this.hubService,
    required this.friendsService,
  });

  @override
  State<HubPanelContent> createState() => _HubPanelContentState();
}

class _HubPanelContentState extends State<HubPanelContent> {
  List<HubMessage> _messages = [];
  Set<String> _excludedSenderIds = {};
  bool _isLoading = true;
  String? _errorMessage;

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

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(
          avatar: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: CroColors.deliveryAmber, borderRadius: BorderRadius.circular(15)),
            child: Text(
              hub.name.isEmpty ? '?' : hub.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          title: hub.name,
          subtitle: '${hub.category ?? 'Landmark'} · anyone can send here',
          onClose: widget.onClose,
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
