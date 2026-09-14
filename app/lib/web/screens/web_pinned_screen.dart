import 'package:flutter/material.dart';

import '../../models/friend.dart';
import '../../models/friend_request.dart';
import '../../models/pinned_bird.dart';
import '../../services/friends_service.dart';
import '../../services/pin_service.dart';
import '../../state/auth_state.dart';
import '../../theme.dart';
import '../../utils/jwt_utils.dart';
import '../widgets/pinned_message_card.dart';

/// The Pinned screen: a "Yours" tab (everything the caller has ever pinned, private or
/// public) and a "Public" world feed (every pin anyone made of a bird that was public when
/// it arrived) - styled like a Hub's message board (see HubPanelContent), since that's the
/// scrolling-list precedent this whole feature is modeled on. The Public tab additionally
/// lets the viewer take down their own bird's pin, mirroring DELETE /pins/{id}'s server-side
/// rule that only the original sender (not just anyone) can do that.
class WebPinnedScreen extends StatefulWidget {
  final AuthState authState;
  final PinService pinService;
  final FriendsService friendsService;

  const WebPinnedScreen({
    super.key,
    required this.authState,
    required this.pinService,
    required this.friendsService,
  });

  @override
  State<WebPinnedScreen> createState() => _WebPinnedScreenState();
}

class _WebPinnedScreenState extends State<WebPinnedScreen> {
  bool _showPublic = false;
  List<PinnedBird> _mine = [];
  List<PinnedBird> _public = [];
  Set<String> _excludedSenderIds = {};
  bool _isLoading = true;
  String? _errorMessage;
  late final String? _currentUserId = jwtSubject(widget.authState.token!);

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
        widget.pinService.listMyPins(token),
        widget.pinService.listPublicPins(token),
        widget.friendsService.getFriends(token),
        widget.friendsService.getIncomingRequests(token),
        widget.friendsService.getOutgoingRequests(token),
      ]);
      final friends = results[2] as List<Friend>;
      final incoming = results[3] as List<FriendRequest>;
      final outgoing = results[4] as List<FriendRequest>;

      if (!mounted) return;
      setState(() {
        _mine = results[0] as List<PinnedBird>;
        _public = results[1] as List<PinnedBird>;
        _excludedSenderIds = {
          ?_currentUserId,
          ...friends.map((f) => f.userId),
          ...incoming.map((r) => r.userId),
          ...outgoing.map((r) => r.userId),
        };
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

  Future<void> _unpin(PinnedBird pin) async {
    await widget.pinService.unpinBird(widget.authState.token!, pin.id);
    if (!mounted) return;
    setState(() {
      _mine = _mine.where((p) => p.id != pin.id).toList();
      _public = _public.where((p) => p.id != pin.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('webPinnedScreen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 74, 26, 0),
          child: Row(
            children: [
              Expanded(child: _segmentButton('Yours', selected: !_showPublic, onTap: () => setState(() => _showPublic = false))),
              const SizedBox(width: 10),
              Expanded(child: _segmentButton('Public world feed', selected: _showPublic, onTap: () => setState(() => _showPublic = true))),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _segmentButton(String label, {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? CroColors.waypointBlue.withValues(alpha: 0.16) : Theme.of(context).colorScheme.surface,
      borderRadius: CroBorders.radius,
      child: InkWell(
        key: Key('webPinnedSegment_${label == 'Yours' ? 'mine' : 'public'}'),
        borderRadius: CroBorders.radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: CroBorders.radius,
            border: Border.all(color: selected ? CroColors.waypointBlue : CroColors.hairline),
          ),
          child: Center(
            child: Text(label, style: CroTextStyles.label(size: 12, color: selected ? CroColors.deepWaypoint : CroColors.fog)),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(key: Key('webPinnedLoading'), child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('webPinnedError'),
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

    final pins = _showPublic ? _public : _mine;
    if (pins.isEmpty) {
      return Center(
        key: Key(_showPublic ? 'webPinnedPublicEmpty' : 'webPinnedMineEmpty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _showPublic
                ? 'No public pins yet - a public bird pinned by its receiver shows up here for everyone'
                : "You haven't pinned any messages yet - tap the pin icon on a delivered bird to save it",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: Key(_showPublic ? 'webPinnedPublicList' : 'webPinnedMineList'),
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 240),
        itemCount: pins.length,
        itemBuilder: (context, i) {
          final pin = pins[i];
          // "Yours" tab: always the receiver's own saved message, always removable (unpin).
          // "Public" tab: only removable when the viewer is the original sender (take-down).
          final canRemove = !_showPublic || pin.senderId == _currentUserId;
          return PinnedMessageCard(
            pin: pin,
            showAddFriend: _showPublic && !_excludedSenderIds.contains(pin.senderId),
            token: widget.authState.token!,
            friendsService: widget.friendsService,
            removeTooltip: _showPublic ? 'Take down' : 'Unpin',
            onRemove: canRemove ? () => _unpin(pin) : null,
          );
        },
      ),
    );
  }
}
