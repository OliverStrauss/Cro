import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/friend_waypoint.dart';
import '../models/waypoint.dart';
import '../services/friends_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../utils/color_utils.dart';

class MapScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;

  MapScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
  })  : waypointService = waypointService ?? WaypointService(),
        friendsService = friendsService ?? FriendsService();

  @override
  State<MapScreen> createState() => MapScreenState();
}

// Public (not the usual private State) so tests can invoke handleMapTap directly -
// flutter_map's internal gesture recognizer doesn't reliably fire from a synthetic
// tester.tap() in the widget test harness, so tests bypass just that gesture-detection
// layer while still exercising the real dialog/save flow that follows.
class MapScreenState extends State<MapScreen> {
  Waypoint? _waypoint;
  List<FriendWaypoint> _friendWaypoints = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final results = await Future.wait<dynamic>([
        widget.waypointService.getWaypoint(token),
        widget.friendsService.getFriendsWaypoints(token),
      ]);
      setState(() {
        _waypoint = results[0] as Waypoint?;
        _friendWaypoints = results[1] as List<FriendWaypoint>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showFriendUsername(String username) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(username)));
  }

  @visibleForTesting
  Future<void> handleMapTap(LatLng point) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _WaypointNameDialog(),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      final saved = await widget.waypointService.saveWaypoint(
        widget.authState.token!,
        name: name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      setState(() => _waypoint = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(key: Key('mapLoadingIndicator'), child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        key: const Key('mapErrorState'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final waypoint = _waypoint;
    return Column(
      children: [
        if (waypoint != null)
          Container(
            key: const Key('waypointBanner'),
            width: double.infinity,
            padding: const EdgeInsets.all(8.0),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Text('Delivery spot: ${waypoint.name}'),
          ),
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: waypoint != null
                  ? LatLng(waypoint.latitude, waypoint.longitude)
                  : const LatLng(0, 0),
              initialZoom: waypoint != null ? 13 : 2,
              onTap: (tapPosition, point) => handleMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.cro_app',
              ),
              if (waypoint != null || _friendWaypoints.isNotEmpty)
                MarkerLayer(markers: [
                  if (waypoint != null)
                    Marker(
                      point: LatLng(waypoint.latitude, waypoint.longitude),
                      child: const Icon(Icons.location_pin, color: Colors.red),
                    ),
                  for (final friendWaypoint in _friendWaypoints)
                    Marker(
                      key: Key('friendMarker_${friendWaypoint.userId}'),
                      point: LatLng(friendWaypoint.latitude, friendWaypoint.longitude),
                      child: GestureDetector(
                        onTap: () => _showFriendUsername(friendWaypoint.username),
                        child: Icon(Icons.location_pin, color: hexToColor(friendWaypoint.color)),
                      ),
                    ),
                ]),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaypointNameDialog extends StatefulWidget {
  @override
  State<_WaypointNameDialog> createState() => _WaypointNameDialogState();
}

class _WaypointNameDialogState extends State<_WaypointNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this waypoint'),
      content: TextField(
        key: const Key('waypointNameField'),
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('saveWaypointButton'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
