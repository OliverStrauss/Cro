import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/bird.dart';
import '../../models/friend.dart';
import '../../models/friend_bird.dart';
import '../../models/hub.dart';
import '../../models/hub_category.dart';
import '../../models/public_bird.dart';
import '../../models/waypoint.dart';
import '../../config.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../utils/flight_path_math.dart';
import '../../widgets/avatar_with_fallback.dart';
import '../widgets/map_marker_pill.dart';

const _amesCenter = LatLng(42.0308, -93.6319);

/// The web Map screen: same flutter_map/OSM foundation and flight-path math as the phone
/// MapScreen (see utils/flight_path_math.dart), restyled per the web design spec. Data is
/// owned by WebShellScreen (not fetched here) so the dock/journey log/nav badges all see the
/// same numbers the map does.
class WebMapScreen extends StatefulWidget {
  final List<Waypoint> ownNests;
  final List<Waypoint> friendWaypoints;
  final List<Bird> birds;
  final List<FriendBird> friendsBirds;
  // Any user's public in-flight birds, not scoped to friends - see BirdService.getPublicBirds.
  // Rendered as a marker with no path line and no origin/destination markers, since a
  // PublicBird carries only a single already-privacy-clamped point (see its own doc comment)
  // and never the flight's real endpoints.
  final List<PublicBird> publicBirds;
  final List<Hub> hubs;
  // Only used for the Trails legend's per-friend rows (username + trail color) -
  // WebShellScreen already loads this for the Friends screen and rail badge.
  final List<Friend> friends;
  // Keyed by hubId - drives a Hub marker's unread-count badge (only shown when > 0), same
  // signal the phone app's MapScreen already fetches via HubService.getUnreadCounts.
  final Map<String, int> hubUnreadCounts;
  // Keyed by own nest id - drives that nest marker's unread-count badge, same residents data
  // WebNestsScreen already uses for its "N waiting" pill (see WebShellData.load()).
  final Map<String, List<Bird>> nestResidentsByNestId;
  final String? selectedNestId;
  final String? selectedHubId;
  // Set when a Place (geocoded) search result is picked - see SearchTrigger.onSelectPlace.
  // Unlike selectedNestId/selectedHubId there's no backing app entity, so this carries the
  // raw point directly instead of an id to look up.
  final LatLng? searchLocation;
  // Whichever bird's panel is currently open (own or a friend's) - that marker gets a glow
  // on the map so "the bird you're following" reads at a glance among the others in flight.
  final String? selectedBirdId;
  // Measured height of the "Your birds" dock - the Trails legend sits this far above the
  // dock's actual current height (collapsed or not - see YourBirdsDock's hidden pill),
  // rather than a fixed offset that would either overlap the dock or leave a gap once it's
  // hidden. flutter_map 8.x has no persistent camera-viewport-padding option (only a one-shot
  // CameraFit.padding for explicit bounds fits), so this doesn't shift the map/markers
  // themselves the way the design doc's own coordinate-rescaling prototype hack did.
  final double bottomInset;
  final ValueChanged<Waypoint> onSelectNest;
  final ValueChanged<Hub> onSelectHub;
  final ValueChanged<Bird> onSelectBird;
  // A friend's bird marker is only tappable when it's public (see _MapFlight/onTap below) -
  // there's nothing to view yet on a still-private one.
  final ValueChanged<FriendBird> onSelectFriendBird;
  final ValueChanged<PublicBird>? onSelectPublicBird;
  // Armed by the Nests screen's "+ Add a nest" button - the next map tap places a nest
  // there instead of selecting whatever marker is underneath it.
  final bool addingNest;
  final ValueChanged<LatLng>? onPlaceNest;
  final VoidCallback? onCancelAddNest;
  // Whether the signed-in user is an admin - only used to word the addingHub banner
  // ("place" for an admin vs "suggest" for anyone else); the actual admin gate is enforced
  // server-side, same as the phone app's Add Hub/Suggest Hub buttons.
  final bool isAdmin;
  // Armed by the Hubs screen's "+ Add Hub"/"+ Suggest Hub" button - the next map tap places
  // a Hub (admin) or submits a suggestion (everyone else) instead of selecting whatever
  // marker is underneath it. Mutually exclusive with addingNest (see WebShellScreen).
  final bool addingHub;
  final ValueChanged<LatLng>? onPlaceHub;
  final VoidCallback? onCancelAddHub;
  // Injectable so a test can read camera.center/zoom after a selection change - same
  // nullable-and-defaulted-if-absent convention FlutterMap's own widget uses for the same
  // reason. Null in real usage; WebMapScreen creates and owns its own otherwise.
  final MapController? mapController;
  // Bumped by WebShellScreen to force a re-center on whichever hub/nest/bird is currently
  // selected, even when that id hasn't changed - _syncCameraFocus below otherwise only
  // triggers on an id change, which is a no-op for "re-center on what's already selected"
  // (e.g. the nest locator button, or a Follow on map button tapped after the user panned
  // away from an already-open panel's target).
  final int focusRequest;

  const WebMapScreen({
    super.key,
    this.mapController,
    required this.ownNests,
    required this.friendWaypoints,
    required this.birds,
    required this.friendsBirds,
    this.publicBirds = const [],
    required this.hubs,
    this.friends = const [],
    this.hubUnreadCounts = const {},
    this.nestResidentsByNestId = const {},
    required this.selectedNestId,
    required this.selectedHubId,
    this.searchLocation,
    this.selectedBirdId,
    required this.bottomInset,
    required this.onSelectNest,
    required this.onSelectHub,
    this.addingNest = false,
    this.onPlaceNest,
    this.onCancelAddNest,
    this.isAdmin = false,
    this.addingHub = false,
    this.onPlaceHub,
    this.onCancelAddHub,
    required this.onSelectBird,
    required this.onSelectFriendBird,
    this.onSelectPublicBird,
    this.focusRequest = 0,
  });

  @override
  State<WebMapScreen> createState() => _WebMapScreenState();
}

class _WebMapScreenState extends State<WebMapScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bobController;
  late final MapController _mapController;
  AnimationController? _cameraAnimationController;

  // Close enough to read the target's own neighborhood, not just "somewhere on the map" -
  // same fixed level a single-own-nest initial view already zooms to (see initialZoom below).
  static const _focusZoom = 14.0;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _mapController = widget.mapController ?? MapController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBob();
  }

  @override
  void didUpdateWidget(covariant WebMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBob();
    _syncCameraFocus(oldWidget);
  }

  // Animates the camera onto whatever nest/hub/in-flight bird was newly selected - a freshly
  // *changed* selection is the only trigger (not every rebuild), so re-tapping the same
  // marker or an unrelated data poll never yanks the view out from under the user. Priority
  // (hub, then nest, then bird) only matters when more than one id changes in the same
  // update, which never happens in practice - each selection path clears the others.
  // A bumped focusRequest overrides the "changed" requirement for whichever target is
  // currently selected, so an explicit re-center request (nest locator, Follow on map)
  // still works when the id was already selected.
  void _syncCameraFocus(WebMapScreen oldWidget) {
    final forced = widget.focusRequest != oldWidget.focusRequest;
    LatLng? target;
    if (widget.selectedHubId != null &&
        (forced || widget.selectedHubId != oldWidget.selectedHubId)) {
      target = _hubLatLng(widget.selectedHubId!);
    } else if (widget.selectedNestId != null &&
        (forced || widget.selectedNestId != oldWidget.selectedNestId)) {
      target = _nestLatLng(widget.selectedNestId!);
    } else if (widget.selectedBirdId != null &&
        (forced || widget.selectedBirdId != oldWidget.selectedBirdId)) {
      // Null for a home bird (nothing to follow) or a friend/public bird (their tap path
      // never routes through here) - _animateCameraTo is simply skipped in that case.
      target = _ownBirdLatLng(widget.selectedBirdId!);
    } else if (widget.searchLocation != null &&
        widget.searchLocation != oldWidget.searchLocation) {
      target = widget.searchLocation;
    }
    if (target != null) _animateCameraTo(target);
  }

  LatLng? _hubLatLng(String id) {
    for (final h in widget.hubs) {
      if (h.id == id) return LatLng(h.latitude, h.longitude);
    }
    return null;
  }

  LatLng? _nestLatLng(String id) {
    for (final n in [...widget.ownNests, ...widget.friendWaypoints]) {
      if (n.id == id) return LatLng(n.latitude, n.longitude);
    }
    return null;
  }

  // Live interpolated position of a still-traveling own bird - null for a home/away/hub
  // bird (nothing to animate to; the panel switch alone is enough) or an unresolvable one.
  LatLng? _ownBirdLatLng(String birdId) {
    for (final bird in widget.birds) {
      if (bird.id != birdId) continue;
      if (!bird.isTraveling ||
          bird.departedAt == null ||
          bird.estimatedArrivalAt == null)
        return null;
      final origin = _nestsById[bird.nestFromId];
      final destination = _nestsById[bird.nestToId];
      if (origin == null || destination == null) return null;
      return interpolatedBirdPosition(
        origin: origin,
        destination: destination,
        departedAt: bird.departedAt!,
        estimatedArrivalAt: bird.estimatedArrivalAt!,
        now: DateTime.now(),
      );
    }
    return null;
  }

  void _animateCameraTo(LatLng target) {
    _cameraAnimationController?.dispose();
    final camera = _mapController.camera;
    final latTween = LatLngTween(begin: camera.center, end: target);
    final zoomTween = Tween<double>(begin: camera.zoom, end: _focusZoom);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
    controller.addListener(
      () => _mapController.move(
        latTween.evaluate(curved),
        zoomTween.evaluate(curved),
      ),
    );
    _cameraAnimationController = controller;
    controller.forward();
  }

  // Respects "reduce motion" (MediaQuery.disableAnimations) - the bob loop is decorative, not
  // informational, so it's simply skipped rather than given a reduced-motion variant.
  void _syncBob() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final hasTraveling =
        !reduceMotion &&
        (widget.birds.any((b) => b.isTraveling) ||
            widget.friendsBirds.isNotEmpty ||
            widget.publicBirds.isNotEmpty);
    if (hasTraveling && !_bobController.isAnimating) {
      _bobController.repeat(reverse: true);
    } else if (!hasTraveling && _bobController.isAnimating) {
      _bobController.stop();
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    _cameraAnimationController?.dispose();
    if (widget.mapController == null) _mapController.dispose();
    super.dispose();
  }

  int _ownNestUnreadCount(Waypoint nest) =>
      (widget.nestResidentsByNestId[nest.id] ?? const [])
          .where((b) => !b.isRead)
          .length;

  // Shared by _resolveFlights (drawing) and _ownBirdLatLng (camera focus) so a Hub's
  // Waypoint projection is only ever built in one place.
  Map<String, Waypoint> get _nestsById => {
    for (final n in [...widget.ownNests, ...widget.friendWaypoints]) n.id: n,
    for (final h in widget.hubs)
      h.id: Waypoint(
        id: h.id,
        userId: h.createdByUserId,
        name: h.name,
        latitude: h.latitude,
        longitude: h.longitude,
      ),
  };

  List<_MapFlight> _resolveFlights() {
    final nestsById = _nestsById;

    final result = <_MapFlight>[];
    for (final bird in widget.birds) {
      if (!bird.isTraveling ||
          bird.departedAt == null ||
          bird.estimatedArrivalAt == null)
        continue;
      final origin = nestsById[bird.nestFromId];
      final destination = nestsById[bird.nestToId];
      if (origin == null || destination == null) continue;
      result.add(
        _MapFlight(
          id: bird.id,
          color: Theme.of(context).colorScheme.primary,
          origin: origin,
          destination: destination,
          departedAt: bird.departedAt!,
          estimatedArrivalAt: bird.estimatedArrivalAt!,
          ownBird: bird,
        ),
      );
    }
    for (final fb in widget.friendsBirds) {
      final origin = nestsById[fb.nestFromId];
      final destination = nestsById[fb.nestToId];
      if (origin == null || destination == null) continue;
      result.add(
        _MapFlight(
          id: fb.id,
          color: fb.color != null ? hexToColor(fb.color!) : CroColors.fog,
          origin: origin,
          destination: destination,
          departedAt: fb.departedAt,
          estimatedArrivalAt: fb.estimatedArrivalAt,
          ownBird: null,
          friendBird: fb,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final flights = _resolveFlights();
    final now = DateTime.now();
    final hasOwnNests = widget.ownNests.isNotEmpty;
    // A selection made from elsewhere (e.g. the dock, or "Follow on map" on the Nests/Hubs
    // screen) can mount a brand-new WebMapScreen instead of updating an existing one - that's
    // an initState, not a didUpdateWidget, so _syncCameraFocus never runs for it. Starting the
    // camera there directly covers that case; _syncCameraFocus's animation still covers a
    // selection made while already on this screen.
    final initialFocus = widget.selectedHubId != null
        ? _hubLatLng(widget.selectedHubId!)
        : widget.selectedNestId != null
        ? _nestLatLng(widget.selectedNestId!)
        : widget.selectedBirdId != null
        ? _ownBirdLatLng(widget.selectedBirdId!)
        : null;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter:
                initialFocus ??
                (hasOwnNests
                    ? LatLng(
                        widget.ownNests.first.latitude,
                        widget.ownNests.first.longitude,
                      )
                    : _amesCenter),
            initialZoom: initialFocus != null
                ? _focusZoom
                : (hasOwnNests ? 13 : 12),
            minZoom: 3,
            cameraConstraint: const CameraConstraint.containLatitude(),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: widget.addingNest
                ? (tapPosition, point) => widget.onPlaceNest?.call(point)
                : widget.addingHub
                ? (tapPosition, point) => widget.onPlaceHub?.call(point)
                : null,
          ),
          children: [
            TileLayer(
              // MapTiler when a key is configured (required for production - see the OSM
              // tile usage policy, tile.openstreetmap.org isn't for production app traffic).
              // Falls back to raw OSM tiles for local dev so nobody needs a MapTiler key
              // just to run the app.
              urlTemplate: mapTilerApiKey.isNotEmpty
                  ? 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$mapTilerApiKey'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.crotheapp.cro_app',
            ),
            if (flights.isNotEmpty)
              // Pulses the in-transit trail's opacity using the same controller/condition as
              // the bird-marker bob below (_bobController only ever runs while something's
              // traveling, which is exactly when flights is non-empty) - reuses the existing
              // loop instead of adding a second one just for this.
              AnimatedBuilder(
                animation: _bobController,
                builder: (context, child) => PolylineLayer(
                  polylines: [
                    for (final f in flights)
                      Polyline(
                        points: curvedFlightPathPoints(
                          origin: f.origin,
                          destination: f.destination,
                        ),
                        color: f.color.withValues(
                          alpha: 0.55 + _bobController.value * 0.45,
                        ),
                        strokeWidth: 2.5,
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                  ],
                ),
              ),
            MarkerLayer(
              markers: [
                // A Place search result has no backing app entity, so it gets a plain pin
                // instead of the Hub/Nest treatment below - cleared on the next search or by
                // picking another map selection (see WebShellScreenState's _select* methods).
                if (widget.searchLocation != null)
                  Marker(
                    key: const Key('webSearchLocationMarker'),
                    point: widget.searchLocation!,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.location_pin,
                      size: 34,
                      color: CroColors.deliveryAmber,
                    ),
                  ),
                for (final hub in widget.hubs)
                  Marker(
                    key: Key('webHubMarker_${hub.id}'),
                    point: LatLng(hub.latitude, hub.longitude),
                    width: 34,
                    height: 34,
                    child: Tooltip(
                      message: hub.name,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onSelectHub(hub),
                          child: _HubMarkerDot(
                            key: Key('webHubMarkerDot_${hub.id}'),
                            name: hub.name,
                            profilePictureUrl: hub.profilePictureUrl,
                            category: hub.category,
                            unreadCount: widget.hubUnreadCounts[hub.id] ?? 0,
                            selected: widget.selectedHubId == hub.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final nest in widget.ownNests)
                  Marker(
                    key: Key('webOwnNestMarker_${nest.id}'),
                    point: LatLng(nest.latitude, nest.longitude),
                    width: 180,
                    height: 46,
                    child: MapMarkerPill(
                      compact: true,
                      selected: widget.selectedNestId == nest.id,
                      selectionColor: CroColors.waypointBlue,
                      onTap: () => widget.onSelectNest(nest),
                      // Still fully-rounded (the default borderRadius of 30) and still
                      // larger than a Hub's marker (radius 15 vs Hub's 12) - nests read
                      // first - but shrunk down from the original 38px avatar after seeing
                      // it live felt oversized next to the rest of the map.
                      avatar: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: CroColors.waypointBlue,
                            child: Text(
                              nest.name.isEmpty
                                  ? '?'
                                  : nest.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: CroColors.surface,
                              ),
                            ),
                          ),
                          if (_ownNestUnreadCount(nest) > 0)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: _UnreadCountBadge(
                                badgeKey: Key('webNestUnreadBadge_${nest.id}'),
                                count: _ownNestUnreadCount(nest),
                              ),
                            ),
                        ],
                      ),
                      name: nest.name,
                      subtitle:
                          '${widget.birds.where((b) => !b.isTraveling && b.currentNestId == nest.id).length} of yours here',
                    ),
                  ),
                for (final fw in widget.friendWaypoints)
                  Marker(
                    key: Key('webFriendNestMarker_${fw.id}'),
                    point: LatLng(fw.latitude, fw.longitude),
                    width: 180,
                    height: 46,
                    child: MapMarkerPill(
                      compact: true,
                      selected: widget.selectedNestId == fw.id,
                      selectionColor: hexToColor(fw.color ?? '#6B7280'),
                      onTap: () => widget.onSelectNest(fw),
                      hasYourBirds: widget.birds.any(
                        (b) => !b.isTraveling && b.currentNestId == fw.id,
                      ),
                      avatar: CircleAvatar(
                        radius: 15,
                        backgroundColor: hexToColor(fw.color ?? '#6B7280'),
                        child: Text(
                          fw.name.isEmpty ? '?' : fw.name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: CroColors.surface,
                          ),
                        ),
                      ),
                      name: fw.name,
                      subtitle: "${fw.username}'s nest",
                    ),
                  ),
                for (final f in flights)
                  Marker(
                    key: Key('webBirdMarker_${f.id}'),
                    point: interpolatedBirdPosition(
                      origin: f.origin,
                      destination: f.destination,
                      departedAt: f.departedAt,
                      estimatedArrivalAt: f.estimatedArrivalAt,
                      now: now,
                    ),
                    width: 34,
                    height: 34,
                    child: Tooltip(
                      message: f.ownBird?.name ?? f.friendBird?.name ?? 'Bird',
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: f.ownBird != null
                              ? () => widget.onSelectBird(f.ownBird!)
                              : (f.isPublicFriendBird
                                    ? () => widget.onSelectFriendBird(
                                        f.friendBird!,
                                      )
                                    : null),
                          child: AnimatedBuilder(
                            animation: _bobController,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(0, -4 * _bobController.value),
                              child: child,
                            ),
                            child: _BirdMarkerDot(
                              key: Key('webBirdMarkerDot_${f.id}'),
                              name:
                                  f.ownBird?.name ??
                                  f.friendBird?.name ??
                                  'Bird',
                              profilePictureUrl:
                                  f.ownBird?.profilePictureUrl ??
                                  f.friendBird?.profilePictureUrl,
                              color: f.color,
                              heading: bearingDegrees(
                                origin: f.origin,
                                destination: f.destination,
                                fraction: elapsedFraction(
                                  departedAt: f.departedAt,
                                  estimatedArrivalAt: f.estimatedArrivalAt,
                                  now: now,
                                ),
                              ),
                              isPublic: f.isPublicFriendBird,
                              hasViewed: f.hasViewed,
                              selected: f.id == widget.selectedBirdId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // A stranger's public bird, from GET /birds/public - deliberately not part
                // of `flights` above, so it never gets a PolylineLayer path or an
                // origin/destination marker: the server only ever gives us the one
                // already-privacy-clamped point in PublicBird.latitude/longitude, not the
                // flight's real endpoints, so there's nothing to draw a line between.
                for (final pb in widget.publicBirds)
                  Marker(
                    key: Key('webPublicBirdMarker_${pb.id}'),
                    point: LatLng(pb.latitude, pb.longitude),
                    width: 34,
                    height: 34,
                    child: Tooltip(
                      message: '${pb.senderUsername}\'s bird',
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onSelectPublicBird?.call(pb),
                          child: AnimatedBuilder(
                            animation: _bobController,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(0, -4 * _bobController.value),
                              child: child,
                            ),
                            child: _BirdMarkerDot(
                              key: Key('webPublicBirdMarkerDot_${pb.id}'),
                              name: pb.senderUsername,
                              profilePictureUrl: pb.senderProfilePictureUrl,
                              color: CroColors.deliveryAmber,
                              heading: 0,
                              isPublic: true,
                              // No per-viewer read-state exists for a global audience (unlike
                              // FriendBird.hasViewed) - true keeps the badge a plain "public"
                              // indicator rather than reading as an unread notification.
                              hasViewed: true,
                              selected: pb.id == widget.selectedBirdId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (widget.addingNest)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: const Key('webAddNestBanner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: CroColors.ink,
                  borderRadius: CroBorders.radius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.ownNests.isEmpty
                          ? 'Click anywhere on the map to place your new nest'
                          : 'Click anywhere on the map to move your nest',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: CroColors.surface,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: const Key('webCancelAddNest'),
                        borderRadius: CroBorders.radiusSmall,
                        onTap: widget.onCancelAddNest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            'Cancel',
                            style: CroTextStyles.label(
                              size: 11.5,
                              color: CroColors.skyTint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.addingHub)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: const Key('webAddHubBanner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: CroColors.ink,
                  borderRadius: CroBorders.radius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isAdmin
                          ? 'Click anywhere on the map to place your new Hub'
                          : 'Click anywhere on the map to suggest a Hub location',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: CroColors.surface,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: const Key('webCancelAddHub'),
                        borderRadius: CroBorders.radiusSmall,
                        onTap: widget.onCancelAddHub,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            'Cancel',
                            style: CroTextStyles.label(
                              size: 11.5,
                              color: CroColors.skyTint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 22,
          bottom: widget.bottomInset + 20,
          child: _TrailsLegend(friends: widget.friends),
        ),
      ],
    );
  }
}

/// Bottom-left legend (05_web_ui_updates.md item 4): the caller's own trail color, then one
/// row per friend (their real trail color/username - the design mock's fabricated "mia_c"/
/// "sam_r" rows are stand-ins for this), then Hubs. Filter chips (also item 4) are
/// deliberately out of scope for now - see issue tracker.
class _TrailsLegend extends StatelessWidget {
  final List<Friend> friends;

  const _TrailsLegend({required this.friends});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (Theme.of(context).colorScheme.primary, 'Your trails'),
      for (final f in friends) (hexToColor(f.color ?? '#6B7280'), f.username),
      (CroColors.deliveryAmber, 'Hubs'),
    ];
    return Container(
      key: const Key('webMapTrailsLegend'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: CroBorders.radius,
        border: Border.all(color: CroColors.hairline),
        boxShadow: [
          BoxShadow(
            color: CroColors.ink.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRAILS', style: CroTextStyles.label(size: 11)),
          const SizedBox(height: 6),
          for (final (color, label) in rows) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: CroTextStyles.data(
                    size: 12,
                    color: CroColors.ink,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BirdMarkerDot extends StatelessWidget {
  final String name;
  final String? profilePictureUrl;
  final Color color;
  final double heading;
  // Only ever true for a friend's bird (see _MapFlight.isPublicFriendBird) - marks it as
  // public/clickable at a glance, distinct from a friend's private bird which the map shows
  // but doesn't badge or let you tap into.
  final bool isPublic;
  final bool hasViewed;
  // Whether this is the bird whose detail panel is currently open - glows the marker so
  // "the one you're following" reads at a glance (see WebMapScreen.selectedBirdId).
  final bool selected;

  const _BirdMarkerDot({
    super.key,
    required this.name,
    this.profilePictureUrl,
    required this.color,
    required this.heading,
    this.isPublic = false,
    this.hasViewed = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              key: const Key('webBirdMarkerGlow'),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.9),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D2B2F33),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: AvatarWithFallback(
              imageUrl: profilePictureUrl,
              initialsSource: name,
              fallbackIcon: Icons.arrow_drop_up,
              fallbackIconTurns: heading / 360,
              fallbackBackgroundColor: color,
              fallbackIconColor: CroColors.surface,
              radius: 9,
            ),
          ),
          if (isPublic)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                key: const Key('webPublicBirdBadge'),
                width: 13,
                height: 13,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasViewed ? CroColors.fog : CroColors.deliveryAmber,
                  shape: BoxShape.circle,
                  border: Border.all(color: CroColors.surface, width: 1),
                ),
                child: const Text(
                  '!',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: CroColors.surface,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The small amber "unread" circle shared by a Hub marker and an own-nest marker - bottom-right
/// of the avatar, showing the real count (capped at "9+" - these badges are 13px, too small for
/// more digits) rather than just a presence dot.
class _UnreadCountBadge extends StatelessWidget {
  final Key badgeKey;
  final int count;

  const _UnreadCountBadge({required this.badgeKey, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: badgeKey,
      width: 13,
      height: 13,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CroColors.deliveryAmber,
        shape: BoxShape.circle,
        border: Border.all(color: CroColors.surface, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: CroTextStyles.label(size: 9, color: CroColors.surface),
      ),
    );
  }
}

/// A Hub marker: same dot-plus-badge language as a friend's public bird marker
/// (_BirdMarkerDot) rather than the old name/category pill - a Hub carries no heading, so the
/// badge is the only thing that changes, and only appears at all when there's something
/// unread (no grey "read" state the way a bird's public badge has, since a Hub's badge isn't
/// also standing in for "this is public").
class _HubMarkerDot extends StatelessWidget {
  final String name;
  final String? profilePictureUrl;
  final String? category;
  final int unreadCount;
  final bool selected;

  const _HubMarkerDot({
    super.key,
    required this.name,
    this.profilePictureUrl,
    this.category,
    this.unreadCount = 0,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              key: const Key('webHubMarkerGlow'),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CroColors.deliveryAmber.withValues(alpha: 0.9),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D2B2F33),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: AvatarWithFallback(
              imageUrl: profilePictureUrl,
              initialsSource: name,
              fallbackIcon: HubCategory.iconFor(category),
              fallbackBackgroundColor: CroColors.deliveryAmber,
              fallbackIconColor: CroColors.surface,
              radius: 11,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              bottom: 0,
              right: 0,
              child: _UnreadCountBadge(
                badgeKey: const Key('webHubUnreadBadge'),
                count: unreadCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _MapFlight {
  final String id;
  final Color color;
  final Waypoint origin;
  final Waypoint destination;
  final DateTime departedAt;
  final DateTime estimatedArrivalAt;
  // Null for a friend's bird - only the caller's own birds open the full bird panel this way.
  final Bird? ownBird;
  // Null for the caller's own bird - a friend's marker is tappable (and badged) only when
  // this is public, resolved via friendBird.isPublic/hasViewed below.
  final FriendBird? friendBird;

  bool get isPublicFriendBird => friendBird?.isPublic ?? false;
  bool get hasViewed => friendBird?.hasViewed ?? false;

  const _MapFlight({
    required this.id,
    required this.color,
    required this.origin,
    required this.destination,
    required this.departedAt,
    required this.estimatedArrivalAt,
    required this.ownBird,
    this.friendBird,
  });
}
