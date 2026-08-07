import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/friend_waypoint.dart';
import '../models/user_profile.dart';
import '../models/waypoint.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../utils/color_utils.dart';
import '../utils/jwt_utils.dart';
import '../widgets/nest_details_dialog.dart';

class MapScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final ProfileService profileService;

  MapScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
  })  : waypointService = waypointService ?? WaypointService(),
        friendsService = friendsService ?? FriendsService(),
        profileService = profileService ?? ProfileService();

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
  UserProfile? _ownProfile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // HomeScreen keeps every tab alive in an IndexedStack rather than rebuilding them on
  // switch, so initState only ever runs once - without an explicit refresh hook, this
  // screen would keep showing whatever waypoint/friend data it first loaded with, even
  // after a friend's color or waypoint changes elsewhere in the app.
  Future<void> refresh() => _loadData();

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final userId = jwtSubject(token);
      final results = await Future.wait<dynamic>([
        widget.waypointService.getWaypoint(token),
        widget.friendsService.getFriendsWaypoints(token),
        if (userId != null) widget.profileService.getUser(userId),
      ]);
      setState(() {
        _waypoint = results[0] as Waypoint?;
        _friendWaypoints = results[1] as List<FriendWaypoint>;
        _ownProfile = userId != null ? results[2] as UserProfile : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showOwnNestDetails(Waypoint waypoint) {
    NestDetailsDialog.show(
      context,
      // Falls back to the waypoint's own name only if the own-profile fetch itself
      // failed - an edge case, not the common path (the fetch is otherwise part of
      // the same all-or-nothing _loadData load as the waypoint itself).
      username: _ownProfile?.username ?? waypoint.name,
      isOwn: true,
      profilePictureUrl: _ownProfile?.profilePictureUrl,
      waypointName: waypoint.name,
      latitude: waypoint.latitude,
      longitude: waypoint.longitude,
    );
  }

  void _showFriendNestDetails(FriendWaypoint friendWaypoint) {
    NestDetailsDialog.show(
      context,
      username: friendWaypoint.username,
      isOwn: false,
      profilePictureUrl: friendWaypoint.profilePictureUrl,
      waypointName: friendWaypoint.waypointName,
      latitude: friendWaypoint.latitude,
      longitude: friendWaypoint.longitude,
    );
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
              // Floor of 3 keeps a whole-country/continent view available while stopping
              // short of the near-zoom-0 world-repeat view that caused "weird behavior"
              // when zoomed all the way out. initialZoom isn't clamped against minZoom on
              // first build (only post-init camera moves are), so the no-waypoint default
              // needs to match the floor directly rather than relying on clamping.
              initialZoom: waypoint != null ? 13 : 3,
              minZoom: 3,
              // Prevents panning past the poles into the background-color void.
              cameraConstraint: const CameraConstraint.containLatitude(),
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
                      key: const Key('ownWaypointMarker'),
                      point: LatLng(waypoint.latitude, waypoint.longitude),
                      child: GestureDetector(
                        onTap: () => _showOwnNestDetails(waypoint),
                        // Same pin shape friends use, so both read as "the same kind of
                        // thing" - still red so the user's own nest stands out at a glance.
                        child: const Icon(Icons.location_pin, color: Colors.red),
                      ),
                    ),
                  for (final friendWaypoint in _friendWaypoints)
                    Marker(
                      key: Key('friendMarker_${friendWaypoint.userId}'),
                      point: LatLng(friendWaypoint.latitude, friendWaypoint.longitude),
                      child: GestureDetector(
                        onTap: () => _showFriendNestDetails(friendWaypoint),
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
