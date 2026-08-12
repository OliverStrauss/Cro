import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/bird.dart';
import '../models/friend_bird.dart';
import '../models/hub.dart';
import '../models/user_profile.dart';
import '../models/waypoint.dart';
import '../services/bird_service.dart';
import '../services/friends_service.dart';
import '../services/hub_service.dart';
import '../services/profile_service.dart';
import '../services/waypoint_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../utils/color_utils.dart';
import '../utils/jwt_utils.dart';
import '../widgets/avatar_with_fallback.dart';
import '../widgets/bird_details_sheet.dart';
import '../widgets/hub_details_sheet.dart';
import '../widgets/hub_name_dialog.dart';
import '../widgets/nest_details_sheet.dart';
import '../widgets/waypoint_name_dialog.dart';
import 'my_nests_screen.dart';

// Ames, IA - the map's default view when a brand-new user has no nests of their own yet.
// Deliberately local rather than a world view, matching the app's "local social" scope for
// Hubs (curated Ames landmarks).
const _amesCenter = LatLng(42.0308, -93.6319);

class MapScreen extends StatefulWidget {
  final AuthState authState;
  final WaypointService waypointService;
  final FriendsService friendsService;
  final ProfileService profileService;
  final BirdService birdService;
  final HubService hubService;
  // When true, this screen is a location-picker pushed from My Nests: tapping the map pops
  // the tapped LatLng back to the caller instead of opening the name-and-save flow itself.
  final bool pickLocationMode;
  // Set when this screen is pushed from "My Nests" via tapping a specific nest row - centers
  // the map there at a close-in zoom instead of the usual "first own nest, zoomed out to 13"
  // default, so tapping a nest actually takes you to it rather than just the general area.
  final LatLng? focusPoint;

  MapScreen({
    super.key,
    required this.authState,
    WaypointService? waypointService,
    FriendsService? friendsService,
    ProfileService? profileService,
    BirdService? birdService,
    HubService? hubService,
    this.pickLocationMode = false,
    this.focusPoint,
  }) : waypointService = waypointService ?? WaypointService(),
       friendsService = friendsService ?? FriendsService(),
       profileService = profileService ?? ProfileService(),
       birdService = birdService ?? BirdService(),
       hubService = hubService ?? HubService();

  @override
  State<MapScreen> createState() => MapScreenState();
}

// Public (not the usual private State) so tests can invoke handleMapTap directly -
// flutter_map's internal gesture recognizer doesn't reliably fire from a synthetic
// tester.tap() in the widget test harness, so tests bypass just that gesture-detection
// layer while still exercising the real dialog/save flow that follows.
class MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  List<Waypoint> _ownNests = [];
  List<Waypoint> _friendWaypoints = [];
  List<Bird> _birds = [];
  List<FriendBird> _friendsBirds = [];
  List<Hub> _hubs = [];
  bool _isAdmin = false;
  // Armed by the admin-only "Add Hub" button - the next map tap places a Hub instead of a
  // nest, then disarms itself. Kept as a simple toggle rather than a separate screen/mode
  // so it doesn't disturb the existing tap-to-add-nest flow at all.
  bool _addHubArmed = false;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _liveUpdateTimer;
  // Drives a gentle shared bob for every traveling-bird marker - one controller for all
  // birds rather than one each, since they're all meant to move in lockstep. Constructed
  // eagerly in initState (not as a lazy `late final` field initializer) so it's always
  // built while the state is definitely mounted. Only actually runs (via
  // _syncBirdBobAnimation) while at least one bird is traveling, rather than
  // unconditionally from initState - an indefinitely-repeating ticker with nothing to
  // animate is a wasted wakeup every frame for as long as this screen is alive.
  late final AnimationController _birdBobController;

  @override
  void initState() {
    super.initState();
    _birdBobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _loadData();
  }

  void _syncBirdBobAnimation() {
    final hasTravelingBirds =
        _birds.any((b) => b.isTraveling) || _friendsBirds.isNotEmpty;
    if (hasTravelingBirds && !_birdBobController.isAnimating) {
      _birdBobController.repeat(reverse: true);
    } else if (!hasTravelingBirds && _birdBobController.isAnimating) {
      _birdBobController.stop();
    }
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
    _liveUpdateTimer
        ?.cancel(); // idempotent - NavigationBar re-fires onDestinationSelected
    // even when re-tapping the already-selected tab.
    _liveUpdateTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshBirds(),
    );
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
      _syncBirdBobAnimation();
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
    _birdBobController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.authState.token!;
      final userId = jwtSubject(token);
      final results = await Future.wait([
        widget.waypointService.listWaypoints(token),
        widget.friendsService.getFriendsWaypoints(token),
        widget.birdService.listBirds(token),
        widget.friendsService.getFriendsBirds(token),
        widget.hubService.listHubs(token),
        if (userId != null) widget.profileService.getUser(userId),
      ]);
      setState(() {
        _ownNests = results[0] as List<Waypoint>;
        _friendWaypoints = results[1] as List<Waypoint>;
        _birds = results[2] as List<Bird>;
        _friendsBirds = results[3] as List<FriendBird>;
        _hubs = results[4] as List<Hub>;
        _isAdmin = results.length > 5 ? (results[5] as UserProfile).isAdmin : false;
        _isLoading = false;
      });
      _syncBirdBobAnimation();
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
      residentBirds: _birds
          .where((b) => b.currentNestId == nest.id && !b.isTraveling)
          .toList(),
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

  void _showHubDetails(Hub hub) {
    HubDetailsSheet.show(
      context,
      name: hub.name,
      category: hub.category,
      profilePictureUrl: hub.profilePictureUrl,
      latitude: hub.latitude,
      longitude: hub.longitude,
    );
  }

  void _showBirdDetails(_TravelingBird tb) {
    BirdDetailsSheet.show(
      context,
      birdId: tb.id,
      name: tb.name,
      type: tb.type,
      senderLabel: tb.senderLabel,
      color: tb.color,
      destinationName: tb.destination.name,
      departedAt: tb.departedAt,
      estimatedArrivalAt: tb.estimatedArrivalAt,
      isPublic: tb.isPublic,
      token: widget.authState.token!,
    );
  }

  // Resolves every in-flight bird visible to the caller - their own (from _birds) plus
  // every accepted friend's (from _friendsBirds, via GET /friends/birds) - to the
  // origin/destination nests its from/to ids refer to. Drops any bird that can't
  // currently be placed on the map (not traveling, missing timing data, or pointing at
  // a nest id that isn't in this user's own-plus-friends-plus-Hubs set - e.g. a stale race
  // with a friend removing a nest mid-flight) rather than crashing. A bird's line/marker
  // color always follows whoever sent it - the theme's primary color for their own birds,
  // or that friend's assigned color for a friend's - never the destination, so two birds
  // converging on the same nest from different senders are still visually distinguishable.
  List<_TravelingBird> _resolveTravelingBirds() {
    final nestsById = <String, Waypoint>{
      for (final nest in [..._ownNests, ..._friendWaypoints]) nest.id: nest,
      // A bird can depart from or land at a Hub (see ComposeAndSendAsync's destination
      // resolution) - projected into a Waypoint-shaped record here purely so the existing
      // curve/marker/bearing math (which only ever reads .latitude/.longitude/.name) keeps
      // working without every one of those functions taking on a Hub-vs-Waypoint union type.
      for (final hub in _hubs)
        hub.id: Waypoint(
          id: hub.id,
          userId: hub.createdByUserId,
          name: hub.name,
          latitude: hub.latitude,
          longitude: hub.longitude,
          profilePictureUrl: hub.profilePictureUrl,
        ),
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
      result.add(
        _TravelingBird(
          id: bird.id,
          name: bird.name,
          type: bird.type,
          senderLabel: 'You',
          color: Theme.of(context).colorScheme.primary,
          origin: origin,
          destination: destination,
          departedAt: departedAt,
          estimatedArrivalAt: estimatedArrivalAt,
          isPublic: bird.isPublic,
        ),
      );
    }
    for (final friendBird in _friendsBirds) {
      final origin = nestsById[friendBird.nestFromId];
      final destination = nestsById[friendBird.nestToId];
      if (origin == null || destination == null) continue;
      result.add(
        _TravelingBird(
          id: friendBird.id,
          name: friendBird.name,
          type: friendBird.type,
          senderLabel: friendBird.username,
          color: friendBird.color != null
              ? hexToColor(friendBird.color!)
              : Theme.of(context).colorScheme.onSurfaceVariant,
          origin: origin,
          destination: destination,
          departedAt: friendBird.departedAt,
          estimatedArrivalAt: friendBird.estimatedArrivalAt,
          isPublic: friendBird.isPublic,
        ),
      );
    }
    return result;
  }

  Future<void> _placeHub(LatLng point) async {
    setState(() => _addHubArmed = false);
    final result = await showDialog<HubNameDialogResult>(
      context: context,
      builder: (context) => const HubNameDialog(),
    );
    if (result == null || result.name.trim().isEmpty) {
      return;
    }

    try {
      final saved = await widget.hubService.createHub(
        widget.authState.token!,
        name: result.name.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
        category: result.category,
      );
      setState(() => _hubs = [..._hubs, saved]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // Mirrors MyNestsScreen's _resolveNestKindToAdd - only asks when both slots are open;
  // otherwise the remaining kind is the only valid choice, and if neither is open there's
  // nothing to add (handled by the caller before this is invoked).
  Future<bool?> _resolveNestKindToAdd() async {
    final hasPrivate = _ownNests.any((n) => !n.isPublic);
    final hasPublic = _ownNests.any((n) => n.isPublic);
    if (hasPrivate && !hasPublic) {
      return true;
    }
    if (hasPublic && !hasPrivate) {
      return false;
    }
    return showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add which kind of nest?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Private nest'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Public nest'),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  Future<void> handleMapTap(LatLng point) async {
    if (widget.pickLocationMode) {
      Navigator.of(context).pop(point);
      return;
    }

    if (_addHubArmed) {
      await _placeHub(point);
      return;
    }

    final hasBothNests =
        _ownNests.any((n) => n.isPublic) && _ownNests.any((n) => !n.isPublic);
    if (hasBothNests) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Both nest slots are full')),
      );
      return;
    }

    final isPublic = await _resolveNestKindToAdd();
    if (isPublic == null || !mounted) {
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => WaypointNameDialog(
        kindLabel: isPublic ? 'Public nest' : 'Private nest',
      ),
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
        isPublic: isPublic,
      );
      setState(() => _ownNests = [..._ownNests, saved]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pickLocationMode ? 'Tap a spot for your new nest' : 'Map',
        ),
        actions: widget.pickLocationMode
            ? null
            : [
                if (_isAdmin)
                  IconButton(
                    key: const Key('addHubButton'),
                    icon: Icon(
                      Icons.add_location_alt,
                      color: _addHubArmed
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                    tooltip: _addHubArmed
                        ? 'Tap the map to place your Hub'
                        : 'Add Hub',
                    onPressed: () =>
                        setState(() => _addHubArmed = !_addHubArmed),
                  ),
                IconButton(
                  key: const Key('myNestsButton'),
                  icon: const Icon(Icons.add_home),
                  tooltip: 'My Nests',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MyNestsScreen(authState: widget.authState),
                    ),
                  ),
                ),
              ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: Key('mapLoadingIndicator'),
        child: CircularProgressIndicator(),
      );
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
    final now =
        DateTime.now(); // one snapshot per build, shared by every bird this frame
    final legendEntries = _buildLegendEntries();
    return FlutterMap(
      options: MapOptions(
        initialCenter:
            widget.focusPoint ??
            (hasOwnNests
                ? LatLng(_ownNests.first.latitude, _ownNests.first.longitude)
                : _amesCenter),
        // Floor of 3 keeps a whole-country/continent view available while stopping
        // short of the near-zoom-0 world-repeat view that caused "weird behavior"
        // when zoomed all the way out. initialZoom isn't clamped against minZoom on
        // first build (only post-init camera moves are), so the no-nest default
        // needs to match the floor directly rather than relying on clamping.
        // A focused nest gets a closer zoom than the general "show all my nests" default -
        // the point is to land the user right on top of the specific nest they tapped.
        // A brand-new user with no nests yet lands on Ames at a local zoom (12), not the
        // old world view - this app is meant to feel local, not global.
        initialZoom: widget.focusPoint != null ? 16 : (hasOwnNests ? 13 : 12),
        minZoom: 3,
        // Prevents panning past the poles into the background-color void.
        cameraConstraint: const CameraConstraint.containLatitude(),
        onTap: (tapPosition, point) => handleMapTap(point),
        // Rotation is disabled entirely (rather than support it) so the flight-line arrows
        // below can always be drawn pointing in their on-screen compass bearing - allowing
        // rotation would mean either re-rotating every arrow to track the camera or letting
        // them visually drift from the direction they're actually pointing.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.cro_app',
        ),
        if (travelingBirds.isNotEmpty)
          PolylineLayer<String>(
            polylines: [
              for (final tb in travelingBirds)
                Polyline<String>(
                  // A gentle curve instead of a straight line - easier to tell apart when
                  // several birds' lines overlap or cross near a shared nest.
                  points: curvedFlightPathPoints(
                    origin: tb.origin,
                    destination: tb.destination,
                  ),
                  color: tb.color,
                  strokeWidth: 3,
                  // Dashed instead of solid carries the "in motion" cue that the removed
                  // directional-arrow markers used to provide.
                  pattern: StrokePattern.dashed(segments: const [8, 6]),
                  hitValue: tb.id,
                ),
            ],
          ),
        if (hasOwnNests ||
            _friendWaypoints.isNotEmpty ||
            travelingBirds.isNotEmpty ||
            _hubs.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final hub in _hubs)
                Marker(
                  key: Key('hubMarker_${hub.id}'),
                  point: LatLng(hub.latitude, hub.longitude),
                  width: 72,
                  height: 62,
                  child: GestureDetector(
                    onTap: () => _showHubDetails(hub),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvatarWithFallback(
                          avatarKey: Key('hubAvatar_${hub.id}'),
                          imageUrl: hub.profilePictureUrl,
                          initialsSource: hub.name,
                          radius: 14,
                          hasBorder: true,
                          borderColor: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(height: 4),
                        _NestLabel(name: hub.name),
                      ],
                    ),
                  ),
                ),
              for (final nest in _ownNests)
                Marker(
                  key: Key('ownNestMarker_${nest.id}'),
                  point: LatLng(nest.latitude, nest.longitude),
                  width: 72,
                  height: 62,
                  child: GestureDetector(
                    onTap: () => _showOwnNestDetails(nest),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Border is always the fixed Waypoint blue, regardless of theme -
                        // this is "the user's own nest" signal, not a themeable role, so a
                        // friend's differently-colored nest stays visually distinguishable.
                        AvatarWithFallback(
                          avatarKey: Key('ownNestAvatar_${nest.id}'),
                          imageUrl: nest.profilePictureUrl,
                          initialsSource: nest.name,
                          radius: 14,
                          hasBorder: true,
                          borderColor: CroColors.waypointBlue,
                        ),
                        const SizedBox(height: 4),
                        _NestLabel(name: nest.name),
                      ],
                    ),
                  ),
                ),
              for (final friendWaypoint in _friendWaypoints)
                Marker(
                  key: Key('friendMarker_${friendWaypoint.id}'),
                  point: LatLng(
                    friendWaypoint.latitude,
                    friendWaypoint.longitude,
                  ),
                  width: 72,
                  height: 62,
                  child: GestureDetector(
                    onTap: () => _showFriendNestDetails(friendWaypoint),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvatarWithFallback(
                          avatarKey: Key(
                            'friendNestAvatar_${friendWaypoint.id}',
                          ),
                          imageUrl: friendWaypoint.profilePictureUrl,
                          initialsSource: friendWaypoint.name,
                          radius: 14,
                          hasBorder: true,
                          borderColor: hexToColor(friendWaypoint.color!),
                        ),
                        const SizedBox(height: 4),
                        _NestLabel(name: friendWaypoint.name),
                      ],
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
                  // Bigger than the painted 18x18 circle (kMinInteractiveDimension, same as
                  // Material's own minimum touch target) - a bird marker moves every 3s and
                  // bobs on top of that, so a tap-sized-to-the-pixels hit target is too easy
                  // to miss on a real touchscreen even though it's precise enough for widget
                  // tests, which tap dead-center.
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                  child: GestureDetector(
                    // Without this, the default HitTestBehavior.deferToChild means a tap only
                    // registers on the painted circle itself, not the full marker box above.
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showBirdDetails(tb),
                    child: AnimatedBuilder(
                      animation: _birdBobController,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -4 * _birdBobController.value),
                        child: child,
                      ),
                      child: BirdTravelMarker(
                        color: tb.color,
                        // The curve's tangent direction at the bird's current position, not
                        // the fixed origin-to-destination chord - so the beak actually turns
                        // to follow the bow in the flight path as the bird travels along it.
                        headingDegrees: bearingDegrees(
                          origin: tb.origin,
                          destination: tb.destination,
                          fraction: elapsedFraction(
                            departedAt: tb.departedAt,
                            estimatedArrivalAt: tb.estimatedArrivalAt,
                            now: now,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (legendEntries.isNotEmpty)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              key: const Key('mapLegend'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in legendEntries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: entry.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            entry.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: CroColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  // One legend row per person currently visible on the map: "You" (fixed Waypoint blue,
  // only if the caller has at least one nest) plus one deduped row per distinct friend
  // username seen on either a friend nest or a friend's in-flight bird - a friend visible
  // only via a bird still gets a row, not just friends with a nest planted.
  List<_LegendEntry> _buildLegendEntries() {
    final colorByUsername = <String, Color>{};
    for (final waypoint in _friendWaypoints) {
      final username = waypoint.username;
      if (username != null && waypoint.color != null) {
        colorByUsername[username] = hexToColor(waypoint.color!);
      }
    }
    for (final friendBird in _friendsBirds) {
      if (friendBird.color != null) {
        colorByUsername.putIfAbsent(
          friendBird.username,
          () => hexToColor(friendBird.color!),
        );
      }
    }

    return [
      if (_ownNests.isNotEmpty)
        const _LegendEntry('You', CroColors.waypointBlue),
      for (final entry in colorByUsername.entries)
        _LegendEntry(entry.key, entry.value),
    ];
  }
}

class _NestLabel extends StatelessWidget {
  final String name;

  const _NestLabel({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: CroColors.ink,
        ),
      ),
    );
  }
}

// A filled circle in the sender's color with a small triangular "beak" pointing along
// headingDegrees - the same north-up compass-bearing convention the removed flight-line
// arrow markers used, now carried by the bird marker itself instead of a separate marker.
// Public (not the usual private-widget convention) and @visibleForTesting so tests can
// reach into the marker's AnimatedBuilder.child and assert on its color/heading directly.
@visibleForTesting
class BirdTravelMarker extends StatelessWidget {
  final Color color;
  final double headingDegrees;

  const BirdTravelMarker({
    super.key,
    required this.color,
    required this.headingDegrees,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D2B2F33),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        // Animated (not a plain Transform.rotate) so a heading change between live-update
        // ticks eases the beak around to the new direction over half a second instead of
        // snapping instantly - reads as the bird gradually turning to face where it's
        // going, rather than teleporting its orientation every 3 seconds.
        AnimatedRotation(
          turns: headingDegrees / 360,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          child: const Icon(Icons.arrow_drop_up, size: 16, color: Colors.white),
        ),
      ],
    );
  }
}

class _LegendEntry {
  final String label;
  final Color color;

  const _LegendEntry(this.label, this.color);
}

// A traveling bird (the caller's own, or an accepted friend's) paired with its
// already-resolved origin and destination Waypoints, non-null departedAt/
// estimatedArrivalAt, and its sender's color - computed once per build and shared
// between the flight-path PolylineLayer and the moving-bird Markers so both stay in
// lockstep and neither re-does the nest lookup/null-checks.
class _TravelingBird {
  final String id;
  final String name;
  final String type;
  // "You" for the caller's own bird, the friend's username for a friend's - who to show
  // as the sender on the bird-details sheet.
  final String senderLabel;
  final Color color;
  final Waypoint origin;
  final Waypoint destination;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;
  final bool isPublic;

  const _TravelingBird({
    required this.id,
    required this.name,
    required this.type,
    required this.senderLabel,
    required this.color,
    required this.origin,
    required this.destination,
    required this.departedAt,
    required this.estimatedArrivalAt,
    this.isPublic = false,
  });
}

// The quadratic bezier control point for the origin-to-destination flight path, in the
// same EPSG:3857 (Web Mercator) projected space PolylineLayer draws in - offset
// perpendicular to the midpoint by 15% of the projected segment length, which is what
// gives the flight path its gentle bow. Shared by every function below that needs to
// place a point on, or a tangent along, that exact curve, so the drawn line, the bird's
// position, and the bird's heading can never drift apart from each other.
(double, double) _flightPathControlPoint(
  double originX,
  double originY,
  double destX,
  double destY,
) {
  final midX = (originX + destX) / 2;
  final midY = (originY + destY) / 2;
  final dx = destX - originX;
  final dy = destY - originY;
  return (midX - dy * 0.15, midY + dx * 0.15);
}

// Point at _fraction_ along the curved flight path (see _flightPathControlPoint) - NOT a
// plain lat/lng lerp, and NOT a straight-line lerp either. Mercator's north-south scale is
// nonlinear in latitude, so a lat/lng lerp would visibly bow off the line drawn under it;
// and a straight origin-to-destination lerp would cut across the curve the flight path is
// actually drawn as, rather than following it. Evaluating the same quadratic bezier the
// drawn line is sampled from is what keeps a point placed with this glued to that line at
// every fraction. Shared by interpolatedBirdPosition (time-based fraction) and
// curveHeadingDegrees (tangent at a fraction) below.
// Public (not prefixed with _) and @visibleForTesting so tests can call it directly
// without pumping a widget.
@visibleForTesting
LatLng positionAtFraction({
  required Waypoint origin,
  required Waypoint destination,
  required double fraction,
}) {
  final clamped = fraction.clamp(0.0, 1.0);
  // Short-circuit the endpoints instead of evaluating the curve at t=0.0/1.0: a
  // project-then-unproject round-trip through Mercator isn't guaranteed bit-exact (trig
  // rounding), so evaluating "all the way" can land a hair off the original lat/lng.
  if (clamped <= 0.0) {
    return LatLng(origin.latitude, origin.longitude);
  }
  if (clamped >= 1.0) {
    return LatLng(destination.latitude, destination.longitude);
  }

  final projection = const Epsg3857().projection;
  final (originX, originY) = projection.projectXY(
    LatLng(origin.latitude, origin.longitude),
  );
  final (destX, destY) = projection.projectXY(
    LatLng(destination.latitude, destination.longitude),
  );
  final (controlX, controlY) = _flightPathControlPoint(
    originX,
    originY,
    destX,
    destY,
  );

  final u = 1 - clamped;
  final x =
      u * u * originX + 2 * u * clamped * controlX + clamped * clamped * destX;
  final y =
      u * u * originY + 2 * u * clamped * controlY + clamped * clamped * destY;
  return projection.unprojectXY(x, y);
}

@visibleForTesting
double elapsedFraction({
  required DateTime departedAt,
  required DateTime estimatedArrivalAt,
  required DateTime now,
}) {
  final totalDuration = estimatedArrivalAt.difference(departedAt);
  if (totalDuration <= Duration.zero) {
    return 1.0;
  }
  return now.difference(departedAt).inMilliseconds /
      totalDuration.inMilliseconds;
}

@visibleForTesting
LatLng interpolatedBirdPosition({
  required Waypoint origin,
  required Waypoint destination,
  required DateTime departedAt,
  required DateTime estimatedArrivalAt,
  required DateTime now,
}) {
  final fraction = elapsedFraction(
    departedAt: departedAt,
    estimatedArrivalAt: estimatedArrivalAt,
    now: now,
  );
  return positionAtFraction(
    origin: origin,
    destination: destination,
    fraction: fraction,
  );
}

// The compass bearing (degrees clockwise from north, [0, 360)) of the curved flight
// path's tangent at _fraction_ - i.e. the direction the bird is actually moving at that
// point along the curve it's drawn on, not the fixed straight-line origin-to-destination
// bearing. Epsg3857's projected Y increases with latitude (north), matching screen "up" on
// a north-up map, so this is the standard atan2(east-component, north-component)
// compass-bearing formula, applied to the bezier's derivative instead of the chord.
//
// Defaults fraction to 0.5: for a quadratic bezier B(t), B'(0.5) = P2 - P0 exactly,
// regardless of the control point - i.e. the midpoint tangent always equals the straight
// origin-to-destination chord direction. That's what keeps this a drop-in replacement for
// the old chord-only bearing at its default.
@visibleForTesting
double bearingDegrees({
  required Waypoint origin,
  required Waypoint destination,
  double fraction = 0.5,
}) {
  final projection = const Epsg3857().projection;
  final (originX, originY) = projection.projectXY(
    LatLng(origin.latitude, origin.longitude),
  );
  final (destX, destY) = projection.projectXY(
    LatLng(destination.latitude, destination.longitude),
  );
  final (controlX, controlY) = _flightPathControlPoint(
    originX,
    originY,
    destX,
    destY,
  );

  final clamped = fraction.clamp(0.0, 1.0);
  final u = 1 - clamped;
  // Derivative of a quadratic bezier: B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1).
  final tangentX =
      2 * u * (controlX - originX) + 2 * clamped * (destX - controlX);
  final tangentY =
      2 * u * (controlY - originY) + 2 * clamped * (destY - controlY);

  final radians = math.atan2(tangentX, tangentY);
  return (radians * 180 / math.pi + 360) % 360;
}

// Samples the same curved flight path positionAtFraction/bearingDegrees evaluate, for
// PolylineLayer to draw - a gentle bow rather than a rigid straight line, easier to tell
// apart when several birds' lines overlap or cross near a shared nest. Sampled (not drawn
// natively) because Polyline only draws straight segments between its points; done in the
// same EPSG:3857 projected space, then unprojected back to LatLng, so the curve matches how
// flutter_map itself projects the map.
@visibleForTesting
List<LatLng> curvedFlightPathPoints({
  required Waypoint origin,
  required Waypoint destination,
  int samples = 20,
}) {
  final points = <LatLng>[];
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    points.add(
      positionAtFraction(origin: origin, destination: destination, fraction: t),
    );
  }
  return points;
}
