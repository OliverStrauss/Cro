import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/bird.dart';
import '../models/friend_bird.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../utils/color_utils.dart';
import '../widgets/avatar_with_fallback.dart';
import '../widgets/nest_details_sheet.dart';
import '../widgets/waypoint_name_dialog.dart';
import 'my_nests_screen.dart';

class MapScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final ProfileService profileService;
  final BirdService birdService;
  // When true, this screen is a location-picker pushed from My Nests: tapping the map pops
  // the tapped LatLng back to the caller instead of opening the name-and-save flow itself.
  final bool pickLocationMode;

  MapScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
    BirdService? birdService,
    this.pickLocationMode = false,
  })  : waypointService = waypointService ?? WaypointService(),
        friendsService = friendsService ?? FriendsService(),
        profileService = profileService ?? ProfileService(),
        birdService = birdService ?? BirdService();

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
  List<Bird> _birds = [];
  List<FriendBird> _friendsBirds = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _liveUpdateTimer;

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

  // HomeScreen calls this when the user switches to the Map tab, and stopLiveUpdates()
  // when they switch away - IndexedStack never disposes this screen on tab switch, so
  // without that symmetric hook a timer started here would keep polling forever in the
  // background.
  void startLiveUpdates() {
    _liveUpdateTimer?.cancel(); // idempotent - NavigationBar re-fires onDestinationSelected
    // even when re-tapping the already-selected tab.
    _liveUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshBirds());
  }

  void stopLiveUpdates() {
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = null;
  }

  Future<void> _refreshBirds() async {
    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.birdService.listBirds(token),
        widget.friendsService.getFriendsBirds(token),
      ]);
      if (!mounted) return;
      setState(() {
        _birds = results[0] as List<Bird>;
        _friendsBirds = results[1] as List<FriendBird>;
      });
    } catch (_) {
      // Swallow - a blip on a silent background poll shouldn't blank an already-rendered
      // map into the full error+Retry state. The next tick retries in 3s.
    }
  }

  @override
  void dispose() {
    // Logout swaps HomeScreen out via ListenableBuilder in main.dart, which disposes
    // this screen while the timer could still be armed - real, not hypothetical.
    _liveUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
        widget.birdService.listBirds(token),
        widget.friendsService.getFriendsBirds(token),
      ]);
      setState(() {
        _ownNests = results[0] as List<Waypoint>;
        _friendWaypoints = results[1] as List<Waypoint>;
        _birds = results[2] as List<Bird>;
        _friendsBirds = results[3] as List<FriendBird>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // Same popup shape as a friend's nest below - own nests additionally get editable
  // name/picture and a "Birds here" list of the caller's own idle birds parked at this
  // nest (never a friend's inbox, never birds sent by anyone but the caller). Refreshes
  // after closing since a rename/re-picture or a send from inside the dialog should be
  // reflected on this screen's own-nest marker and bird data too.
  Future<void> _showOwnNestDetails(Waypoint nest) async {
    await NestDetailsSheet.show(
      context,
      username: nest.name,
      isOwn: true,
      profilePictureUrl: nest.profilePictureUrl,
      waypointId: nest.id,
      waypointName: nest.name,
      latitude: nest.latitude,
      longitude: nest.longitude,
      authState: widget.authState,
      ringColor: CroColors.waypointBlue,
      residentBirds: _birds.where((b) => b.currentNestId == nest.id && !b.isTraveling).toList(),
      waypointService: widget.waypointService,
      friendsService: widget.friendsService,
      birdService: widget.birdService,
      profileService: widget.profileService,
    );
    refresh();
  }

  void _showFriendNestDetails(Waypoint friendWaypoint) {
    NestDetailsSheet.show(
      context,
      username: friendWaypoint.username!,
      isOwn: false,
      profilePictureUrl: friendWaypoint.profilePictureUrl,
      waypointId: friendWaypoint.id,
      waypointName: friendWaypoint.name,
      latitude: friendWaypoint.latitude,
      longitude: friendWaypoint.longitude,
      authState: widget.authState,
      ringColor: hexToColor(friendWaypoint.color!),
    );
  }

  // Resolves every in-flight bird visible to the caller - their own (from _birds) plus
  // every accepted friend's (from _friendsBirds, via GET /friends/birds) - to the
  // origin/destination nests its from/to ids refer to. Drops any bird that can't
  // currently be placed on the map (not traveling, missing timing data, or pointing at
  // a nest id that isn't in this user's own-plus-friends nest set - e.g. a stale race
  // with a friend removing a nest mid-flight) rather than crashing. A bird's line/marker
  // color always follows whoever sent it - the theme's primary color for their own birds,
  // or that friend's assigned color for a friend's - never the destination, so two birds
  // converging on the same nest from different senders are still visually distinguishable.
  List<_TravelingBird> _resolveTravelingBirds() {
    final nestsById = <String, Waypoint>{
      for (final nest in [..._ownNests, ..._friendWaypoints]) nest.id: nest,
    };

    final result = <_TravelingBird>[];
    for (final bird in _birds) {
      if (!bird.isTraveling) continue;
      final departedAt = bird.departedAt;
      final estimatedArrivalAt = bird.estimatedArrivalAt;
      if (departedAt == null || estimatedArrivalAt == null) continue;
      final origin = nestsById[bird.nestFromId];
      final destination = nestsById[bird.nestToId];
      if (origin == null || destination == null) continue;
      result.add(_TravelingBird(
        id: bird.id,
        color: Theme.of(context).colorScheme.primary,
        origin: origin,
        destination: destination,
        departedAt: departedAt,
        estimatedArrivalAt: estimatedArrivalAt,
      ));
    }
    for (final friendBird in _friendsBirds) {
      final origin = nestsById[friendBird.nestFromId];
      final destination = nestsById[friendBird.nestToId];
      if (origin == null || destination == null) continue;
      result.add(_TravelingBird(
        id: friendBird.id,
        color: friendBird.color != null
            ? hexToColor(friendBird.color!)
            : Theme.of(context).colorScheme.onSurfaceVariant,
        origin: origin,
        destination: destination,
        departedAt: friendBird.departedAt,
        estimatedArrivalAt: friendBird.estimatedArrivalAt,
      ));
    }
    return result;
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
    final travelingBirds = _resolveTravelingBirds();
    final now = DateTime.now(); // one snapshot per build, shared by every bird this frame
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
        // Rotation is disabled entirely (rather than support it) so the flight-line arrows
        // below can always be drawn pointing in their on-screen compass bearing - allowing
        // rotation would mean either re-rotating every arrow to track the camera or letting
        // them visually drift from the direction they're actually pointing.
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.cro_app',
        ),
        if (travelingBirds.isNotEmpty)
          PolylineLayer<String>(polylines: [
            for (final tb in travelingBirds)
              Polyline<String>(
                points: [
                  LatLng(tb.origin.latitude, tb.origin.longitude),
                  LatLng(tb.destination.latitude, tb.destination.longitude),
                ],
                color: tb.color,
                strokeWidth: 3,
                hitValue: tb.id,
              ),
          ]),
        if (hasOwnNests || _friendWaypoints.isNotEmpty || travelingBirds.isNotEmpty)
          MarkerLayer(markers: [
            for (final nest in _ownNests)
              Marker(
                key: Key('ownNestMarker_${nest.id}'),
                point: LatLng(nest.latitude, nest.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showOwnNestDetails(nest),
                  // Border is always the fixed Waypoint blue, regardless of theme -
                  // this is "the user's own nest" signal, not a themeable role, so a
                  // friend's differently-colored nest stays visually distinguishable.
                  child: AvatarWithFallback(
                    avatarKey: Key('ownNestAvatar_${nest.id}'),
                    imageUrl: nest.profilePictureUrl,
                    initialsSource: nest.name,
                    radius: 14,
                    hasBorder: true,
                    borderColor: CroColors.waypointBlue,
                  ),
                ),
              ),
            for (final friendWaypoint in _friendWaypoints)
              Marker(
                key: Key('friendMarker_${friendWaypoint.id}'),
                point: LatLng(friendWaypoint.latitude, friendWaypoint.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showFriendNestDetails(friendWaypoint),
                  child: AvatarWithFallback(
                    avatarKey: Key('friendNestAvatar_${friendWaypoint.id}'),
                    imageUrl: friendWaypoint.profilePictureUrl,
                    initialsSource: friendWaypoint.name,
                    radius: 14,
                    hasBorder: true,
                    borderColor: hexToColor(friendWaypoint.color!),
                  ),
                ),
              ),
            for (final tb in travelingBirds)
              Marker(
                key: Key('birdMarker_${tb.id}'),
                point: interpolatedBirdPosition(
                  origin: tb.origin,
                  destination: tb.destination,
                  departedAt: tb.departedAt,
                  estimatedArrivalAt: tb.estimatedArrivalAt,
                  now: now,
                ),
                // Same tracking icon already used for birds on BirdsScreen, colored per
                // the sender rule above instead of hardcoded red. Purely visual - no
                // tap/dialog, unlike the nest markers.
                child: Icon(Icons.flutter_dash, color: tb.color),
              ),
            for (final tb in travelingBirds)
              for (final fraction in _arrowFractions)
                Marker(
                  key: Key('flightArrow_${tb.id}_$fraction'),
                  point: positionAtFraction(origin: tb.origin, destination: tb.destination, fraction: fraction),
                  width: 16,
                  height: 16,
                  // Points up by default, rotated clockwise by the line's compass bearing -
                  // subtle (low opacity, small) so it reads as a direction hint on the line
                  // rather than competing with the bird marker itself.
                  child: Transform.rotate(
                    angle: bearingDegrees(origin: tb.origin, destination: tb.destination) * math.pi / 180,
                    child: Icon(Icons.arrow_upward, size: 14, color: tb.color.withValues(alpha: 0.6)),
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

// A traveling bird (the caller's own, or an accepted friend's) paired with its
// already-resolved origin and destination Waypoints, non-null departedAt/
// estimatedArrivalAt, and its sender's color - computed once per build and shared
// between the flight-path PolylineLayer and the moving-bird Markers so both stay in
// lockstep and neither re-does the nest lookup/null-checks.
class _TravelingBird {
  final String id;
  final Color color;
  final Waypoint origin;
  final Waypoint destination;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;

  const _TravelingBird({
    required this.id,
    required this.color,
    required this.origin,
    required this.destination,
    required this.departedAt,
    required this.estimatedArrivalAt,
  });
}

// Lerp by _fraction_, in the same EPSG:3857 (Web Mercator) projected space PolylineLayer
// draws its straight line in - NOT a plain lat/lng lerp. Mercator's north-south scale is
// nonlinear in latitude, so a lat/lng lerp and a projected-space lerp only agree on the
// equator; anywhere else (and especially on long north-south legs) the lat/lng version
// visibly bows off the line drawn under it. Projecting first makes the two mathematically
// the same line, so a point placed with this can never drift off it. Shared by
// interpolatedBirdPosition (time-based fraction) and the flight-arrow markers (fixed
// fractions along the line) below.
// Public (not prefixed with _) and @visibleForTesting so tests can call it directly
// without pumping a widget.
@visibleForTesting
LatLng positionAtFraction({
  required Waypoint origin,
  required Waypoint destination,
  required double fraction,
}) {
  final clamped = fraction.clamp(0.0, 1.0);
  // Short-circuit the endpoints instead of lerping with fraction 0.0/1.0: a project-then-
  // unproject round-trip through Mercator isn't guaranteed bit-exact (trig rounding), so
  // lerping "all the way" can land a hair off the original lat/lng.
  if (clamped <= 0.0) {
    return LatLng(origin.latitude, origin.longitude);
  }
  if (clamped >= 1.0) {
    return LatLng(destination.latitude, destination.longitude);
  }

  final projection = const Epsg3857().projection;
  final (originX, originY) = projection.projectXY(LatLng(origin.latitude, origin.longitude));
  final (destX, destY) = projection.projectXY(LatLng(destination.latitude, destination.longitude));

  return projection.unprojectXY(
    originX + (destX - originX) * clamped,
    originY + (destY - originY) * clamped,
  );
}

@visibleForTesting
LatLng interpolatedBirdPosition({
  required Waypoint origin,
  required Waypoint destination,
  required DateTime departedAt,
  required DateTime estimatedArrivalAt,
  required DateTime now,
}) {
  final totalDuration = estimatedArrivalAt.difference(departedAt);
  if (totalDuration <= Duration.zero) {
    return LatLng(destination.latitude, destination.longitude);
  }

  final fraction = now.difference(departedAt).inMilliseconds / totalDuration.inMilliseconds;
  return positionAtFraction(origin: origin, destination: destination, fraction: fraction);
}

// The compass bearing (degrees clockwise from north, [0, 360)) of the straight
// projected-space line from origin to destination - i.e. the visual direction that line
// is actually drawn in on an unrotated, north-up map, not the great-circle initial bearing
// (which would drift from the rendered straight line over long routes). Epsg3857's
// projected Y increases with latitude (north), matching screen "up" on a north-up map, so
// this is the standard atan2(east-component, north-component) compass-bearing formula.
@visibleForTesting
double bearingDegrees({
  required Waypoint origin,
  required Waypoint destination,
}) {
  final projection = const Epsg3857().projection;
  final (originX, originY) = projection.projectXY(LatLng(origin.latitude, origin.longitude));
  final (destX, destY) = projection.projectXY(LatLng(destination.latitude, destination.longitude));

  final radians = math.atan2(destX - originX, destY - originY);
  return (radians * 180 / math.pi + 360) % 360;
}

// Fixed fractions along a flight line at which to draw a small directional arrow, evenly
// spaced but not at the endpoints themselves (0.0/1.0 sit right on the nest markers).
const List<double> _arrowFractions = [0.2, 0.4, 0.6, 0.8];
