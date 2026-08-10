import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../widgets/send_bird_dialog.dart';

class NestBirdsScreen extends StatefulWidget {
  final String title;
  final String nestId;
  final List<Bird> birds;
  final String callerUserId;
  final BirdService birdService;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final AuthState authState;

  const NestBirdsScreen({
    super.key,
    required this.title,
    required this.nestId,
    required this.birds,
    required this.callerUserId,
    required this.birdService,
    required this.waypointService,
    required this.friendsService,
    required this.authState,
  });

  @override
  State<NestBirdsScreen> createState() => _NestBirdsScreenState();
}

class _NestBirdsScreenState extends State<NestBirdsScreen> {
  late List<Bird> _birds = widget.birds;

  Future<void> _handleTap(Bird bird) async {
    final token = widget.authState.token!;
    if (bird.userId == widget.callerUserId && !bird.isTraveling) {
      await _openSendFlow(bird, token);
    } else {
      await _openReadDialog(bird, token);
    }
  }

  Future<void> _openSendFlow(Bird bird, String token) async {
    try {
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
      ]);
      final ownNests = results[0].where((w) => w.id != widget.nestId);
      final friendNests = results[1];

      final destinations = [
        ...ownNests.map((w) => SendBirdDestination(nestId: w.id, label: w.name)),
        ...friendNests.map((w) => SendBirdDestination(nestId: w.id, label: '${w.name} (${w.username})')),
      ];

      if (!mounted) return;
      final result = await showDialog<SendBirdResult>(
        context: context,
        builder: (_) => SendBirdDialog(destinations: destinations),
      );
      if (result == null) return;

      await widget.birdService.sendBird(token, bird.id, nestId: result.nestId, content: result.content);
      if (!mounted) return;
      setState(() => _birds = _birds.where((b) => b.id != bird.id).toList());
      _showToast('${bird.name} is on its way!');
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _openReadDialog(Bird bird, String token) async {
    if (!bird.isRead) {
      try {
        await widget.birdService.markBirdRead(token, bird.id);
        if (!mounted) return;
        setState(() {
          _birds = _birds.map((b) => b.id == bird.id ? _markedRead(b) : b).toList();
        });
      } catch (e) {
        _showToast(e.toString(), isError: true);
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(bird.name),
        content: Text(bird.content ?? '(no message)'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Bird _markedRead(Bird bird) => Bird(
        id: bird.id,
        userId: bird.userId,
        name: bird.name,
        currentNestId: bird.currentNestId,
        isTraveling: bird.isTraveling,
        nestFromId: bird.nestFromId,
        nestToId: bird.nestToId,
        speed: bird.speed,
        content: bird.content,
        type: bird.type,
        departedAt: bird.departedAt,
        estimatedArrivalAt: bird.estimatedArrivalAt,
        isRead: true,
      );

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView.builder(
          itemCount: _birds.length,
          itemBuilder: (context, index) {
            final bird = _birds[index];
            return ListTile(
              key: Key('birdTile_${bird.id}'),
              title: Text(bird.name),
              trailing: !bird.isRead
                  ? Icon(
                      Icons.circle,
                      size: 10,
                      key: Key('unreadDot_${bird.id}'),
                      color: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onTap: () => _handleTap(bird),
            );
          },
        ),
      );
}
