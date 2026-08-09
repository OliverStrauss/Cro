import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../utils/jwt_utils.dart';
import 'nest_birds_screen.dart';

class BirdsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final BirdService birdService;
  final FriendsService friendsService;

  BirdsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    BirdService? birdService,
    FriendsService? friendsService,
  })  : waypointService = waypointService ?? WaypointService(),
        birdService = birdService ?? BirdService(),
        friendsService = friendsService ?? FriendsService();

  @override
  State<BirdsScreen> createState() => _BirdsScreenState();
}

class _BirdsScreenState extends State<BirdsScreen> {
  List<Waypoint> _nests = [];
  List<Bird> _ownBirds = [];
  Map<String, List<Bird>> _residentsByNestId = {};
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
        widget.waypointService.listWaypoints(token),
        widget.birdService.listBirds(token),
      ]);
      final nests = results[0] as List<Waypoint>;
      final ownBirds = results[1] as List<Bird>;

      // A nest can hold birds the caller doesn't own (a friend's delivery), so counts and
      // unread badges need the full resident list per nest, not just the caller's own birds.
      final residentsByNestId = <String, List<Bird>>{};
      for (final nest in nests) {
        residentsByNestId[nest.id] = await widget.birdService.getNestResidents(token, nest.id);
      }

      setState(() {
        _nests = nests;
        _ownBirds = ownBirds;
        _residentsByNestId = residentsByNestId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openNestBirds(String title, String nestId, List<Bird> birds) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => NestBirdsScreen(
            title: title,
            nestId: nestId,
            birds: birds,
            callerUserId: jwtSubject(widget.authState.token!)!,
            birdService: widget.birdService,
            waypointService: widget.waypointService,
            friendsService: widget.friendsService,
            authState: widget.authState,
          ),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Birds')),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('birdsLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('birdsErrorState'),
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

    final unassigned = _ownBirds.where((b) => b.currentNestId == null && !b.isTraveling).toList();

    if (_nests.isEmpty && unassigned.isEmpty) {
      return const Center(key: Key('noBirdsMessage'), child: Text('No birds yet'));
    }

    return ListView(
      children: [
        ..._nests.map((nest) {
          final residents = _residentsByNestId[nest.id] ?? [];
          final unreadCount = residents.where((b) => !b.isRead).length;
          return Card(
            key: Key('birdNestTile_${nest.id}'),
            child: ListTile(
              title: Text(nest.name),
              subtitle: Text(
                '${residents.length} ${residents.length == 1 ? 'bird' : 'birds'}'
                '${unreadCount > 0 ? ' • $unreadCount unread' : ''}',
              ),
              trailing: unreadCount > 0
                  ? Icon(Icons.circle, size: 10, key: Key('unreadBadge_${nest.id}'), color: Theme.of(context).colorScheme.error)
                  : null,
              onTap: () => _openNestBirds(nest.name, nest.id, residents),
            ),
          );
        }),
        if (unassigned.isNotEmpty)
          Card(
            key: const Key('unassignedBirdsTile'),
            child: ListTile(
              title: const Text('Unassigned'),
              subtitle: Text('${unassigned.length} ${unassigned.length == 1 ? 'bird' : 'birds'}'),
            ),
          ),
      ],
    );
  }
}
