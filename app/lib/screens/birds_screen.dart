import 'package:flutter/material.dart';

import '../models/bird.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import 'nest_birds_screen.dart';

class BirdsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final BirdService birdService;

  BirdsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    BirdService? birdService,
  })  : waypointService = waypointService ?? WaypointService(),
        birdService = birdService ?? BirdService();

  @override
  State<BirdsScreen> createState() => _BirdsScreenState();
}

class _BirdsScreenState extends State<BirdsScreen> {
  List<Waypoint> _nests = [];
  List<Bird> _birds = [];
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
      setState(() {
        _nests = results[0] as List<Waypoint>;
        _birds = results[1] as List<Bird>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String?, List<Bird>> get _birdsByNestId {
    final map = <String?, List<Bird>>{};
    for (final bird in _birds) {
      map.putIfAbsent(bird.currentNestId, () => []).add(bird);
    }
    return map;
  }

  void _openNestBirds(String title, List<Bird> birds) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NestBirdsScreen(title: title, birds: birds),
    ));
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

    final byNest = _birdsByNestId;
    final unassigned = byNest[null] ?? [];

    if (_nests.isEmpty && unassigned.isEmpty) {
      return const Center(key: Key('noBirdsMessage'), child: Text('No birds yet'));
    }

    return ListView(
      children: [
        ..._nests.map((nest) {
          final birds = byNest[nest.id] ?? [];
          return Card(
            key: Key('birdNestTile_${nest.id}'),
            child: ListTile(
              title: Text(nest.name),
              subtitle: Text('${birds.length} ${birds.length == 1 ? 'bird' : 'birds'}'),
              onTap: () => _openNestBirds(nest.name, birds),
            ),
          );
        }),
        if (unassigned.isNotEmpty)
          Card(
            key: const Key('unassignedBirdsTile'),
            child: ListTile(
              title: const Text('Unassigned'),
              subtitle: Text('${unassigned.length} ${unassigned.length == 1 ? 'bird' : 'birds'}'),
              onTap: () => _openNestBirds('Unassigned', unassigned),
            ),
          ),
      ],
    );
  }
}
