import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/waypoint.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../widgets/waypoint_name_dialog.dart';
import 'map_screen.dart';

class MyNestsScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  // Forwarded to the MapScreen pushed by the "add" flow (see _addNest below) - kept
  // injectable for tests, same as every other service on this screen.
  final FriendsService friendsService;
  final ProfileService profileService;

  MyNestsScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
  })  : waypointService = waypointService ?? WaypointService(),
        friendsService = friendsService ?? FriendsService(),
        profileService = profileService ?? ProfileService();

  @override
  State<MyNestsScreen> createState() => _MyNestsScreenState();
}

class _MyNestsScreenState extends State<MyNestsScreen> {
  List<Waypoint> _nests = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNests();
  }

  Future<void> _loadNests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final nests = await widget.waypointService.listWaypoints(widget.authState.token!);
      setState(() {
        _nests = nests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _renameNest(Waypoint nest) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(initialName: nest.name),
    );
    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    try {
      await widget.waypointService.updateWaypoint(
        widget.authState.token!,
        nest.id,
        name: newName.trim(),
        latitude: nest.latitude,
        longitude: nest.longitude,
      );
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _deleteNest(Waypoint nest) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this nest?'),
        content: Text('"${nest.name}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            key: const Key('confirmDeleteNestButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await widget.waypointService.deleteWaypoint(widget.authState.token!, nest.id);
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

  Future<void> _addNest() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          authState: widget.authState,
          waypointService: widget.waypointService,
          pickLocationMode: true,
        ),
      ),
    );
    if (point == null || !mounted) {
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => const WaypointNameDialog(),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await widget.waypointService.createWaypoint(
        widget.authState.token!,
        name: name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      await _loadNests();
    } catch (e) {
      _showToast(e.toString(), isError: true);
    }
  }

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
      appBar: AppBar(title: const Text('My Nests')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        key: const Key('addNestButton'),
        onPressed: _addNest,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('myNestsLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('myNestsErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadNests, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_nests.isEmpty) {
      return const Center(
        key: Key('noNestsMessage'),
        child: Text('No nests yet - tap + to add one'),
      );
    }

    return ListView.builder(
      itemCount: _nests.length,
      itemBuilder: (context, index) {
        final nest = _nests[index];
        return Card(
          key: Key('nestTile_${nest.id}'),
          child: ListTile(
            title: Text(nest.name),
            subtitle: Text('(${nest.latitude.toStringAsFixed(4)}, ${nest.longitude.toStringAsFixed(4)})'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('renameNestButton_${nest.id}'),
                  icon: const Icon(Icons.edit),
                  onPressed: () => _renameNest(nest),
                ),
                IconButton(
                  key: Key('deleteNestButton_${nest.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteNest(nest),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
