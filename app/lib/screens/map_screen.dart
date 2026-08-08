import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/user_profile.dart';
import '../models/waypoint.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../utils/color_utils.dart';
import '../utils/jwt_utils.dart';
import '../widgets/nest_details_dialog.dart';
import '../widgets/waypoint_name_dialog.dart';
import 'my_nests_screen.dart';

class MapScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final ProfileService profileService;
  // When true, this screen is a location-picker pushed from My Nests: tapping the map pops
  // the tapped LatLng back to the caller instead of opening the name-and-save flow itself.
  final bool pickLocationMode;

  MapScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
    this.pickLocationMode = false,
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
  List<Waypoint> _ownNests = [];
  List<Waypoint> _friendWaypoints = [];
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
  // screen would keep showing whatever nest/friend data it first loaded with, even
  // after a friend's color or nest changes elsewhere in the app.
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
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
        if (userId != null) widget.profileService.getUser(userId),
      ]);
      setState(() {
        _ownNests = results[0] as List<Waypoint>;
        _friendWaypoints = results[1] as List<Waypoint>;
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

  void _showOwnNestDetails(Waypoint nest) {
    NestDetailsDialog.show(
      context,
      // Falls back to the nest's own name only if the own-profile fetch itself
      // failed - an edge case, not the common path (the fetch is otherwise part of
      // the same all-or-nothing _loadData load as the nest itself).
      username: _ownProfile?.username ?? nest.name,
      isOwn: true,
      profilePictureUrl: _ownProfile?.profilePictureUrl,
      waypointId: nest.id,
      waypointName: nest.name,
      latitude: nest.latitude,
      longitude: nest.longitude,
      authState: widget.authState,
    );
  }

  void _showFriendNestDetails(Waypoint friendWaypoint) {
    NestDetailsDialog.show(
      context,
      username: friendWaypoint.username!,
      isOwn: false,
      profilePictureUrl: friendWaypoint.profilePictureUrl,
      waypointId: friendWaypoint.id,
      waypointName: friendWaypoint.name,
      latitude: friendWaypoint.latitude,
      longitude: friendWaypoint.longitude,
      authState: widget.authState,
    );
  }

  @visibleForTesting
  Future<void> handleMapTap(LatLng point) async {
    if (widget.pickLocationMode) {
      Navigator.of(context).pop(point);
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
      final saved = await widget.waypointService.createWaypoint(
        widget.authState.token!,
        name: name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
      );
      setState(() => _ownNests = [..._ownNests, saved]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickLocationMode ? 'Tap a spot for your new nest' : 'Map'),
        actions: widget.pickLocationMode
            ? null
            : [
                IconButton(
                  key: const Key('myNestsButton'),
                  icon: const Icon(Icons.add_home),
                  tooltip: 'My Nests',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MyNestsScreen(authState: widget.authState)),
                  ),
                ),
              ],
      ),
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

    final hasOwnNests = _ownNests.isNotEmpty;
    return FlutterMap(
      options: MapOptions(
        initialCenter:
            hasOwnNests ? LatLng(_ownNests.first.latitude, _ownNests.first.longitude) : const LatLng(0, 0),
        // Floor of 3 keeps a whole-country/continent view available while stopping
        // short of the near-zoom-0 world-repeat view that caused "weird behavior"
        // when zoomed all the way out. initialZoom isn't clamped against minZoom on
        // first build (only post-init camera moves are), so the no-nest default
        // needs to match the floor directly rather than relying on clamping.
        initialZoom: hasOwnNests ? 13 : 3,
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
        if (hasOwnNests || _friendWaypoints.isNotEmpty)
          MarkerLayer(markers: [
            for (final nest in _ownNests)
              Marker(
                key: Key('ownNestMarker_${nest.id}'),
                point: LatLng(nest.latitude, nest.longitude),
                child: GestureDetector(
                  onTap: () => _showOwnNestDetails(nest),
                  // Same pin shape friends use, so both read as "the same kind of
                  // thing" - still red so the user's own nests stand out at a glance.
                  child: const Icon(Icons.house, color: Colors.red),
                ),
              ),
            for (final friendWaypoint in _friendWaypoints)
              Marker(
                key: Key('friendMarker_${friendWaypoint.id}'),
                point: LatLng(friendWaypoint.latitude, friendWaypoint.longitude),
                child: GestureDetector(
                  onTap: () => _showFriendNestDetails(friendWaypoint),
                  child: Icon(Icons.location_pin, color: hexToColor(friendWaypoint.color!)),
                ),
              ),
          ]),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
