import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/bird.dart';
import '../../models/friend_bird.dart';
import '../../models/hub.dart';
import '../../models/waypoint.dart';
import '../../theme.dart';
import '../../utils/color_utils.dart';
import '../../utils/flight_path_math.dart';
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
  final List<Hub> hubs;
  final String? selectedNestId;
  final String? selectedHubId;
  // Whichever bird's panel is currently open (own or a friend's) - that marker gets a glow
  // on the map so "the bird you're following" reads at a glance among the others in flight.
  final String? selectedBirdId;
  // Measured height of the "Your birds" dock, passed down so a future bottom-anchored
  // overlay (a trail legend, a toast) can sit above it instead of underneath it -
  // flutter_map 8.x has no persistent camera-viewport-padding option (only a one-shot
  // CameraFit.padding for explicit bounds fits), so this doesn't shift the map/markers
  // themselves the way the design doc's own coordinate-rescaling prototype hack did.
  final double bottomInset;
  final ValueChanged<Waypoint> onSelectNest;
  final ValueChanged<Hub> onSelectHub;
  final ValueChanged<Bird> onSelectBird;
  // A friend's bird marker is only tappable when it's public (see _MapFlight/onTap below) -
  // there's nothing to view yet on a still-private one.
  final ValueChanged<FriendBird> onSelectFriendBird;
  // Armed by the Nests screen's "+ Add a nest" button - the next map tap places a nest
  // there instead of selecting whatever marker is underneath it.
  final bool addingNest;
  final ValueChanged<LatLng>? onPlaceNest;
  final VoidCallback? onCancelAddNest;

  const WebMapScreen({
    super.key,
    required this.ownNests,
    required this.friendWaypoints,
    required this.birds,
    required this.friendsBirds,
    required this.hubs,
    required this.selectedNestId,
    required this.selectedHubId,
    this.selectedBirdId,
    required this.bottomInset,
    required this.onSelectNest,
    required this.onSelectHub,
    this.addingNest = false,
    this.onPlaceNest,
    this.onCancelAddNest,
    required this.onSelectBird,
    required this.onSelectFriendBird,
  });

  @override
  State<WebMapScreen> createState() => _WebMapScreenState();
}

class _WebMapScreenState extends State<WebMapScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _syncBob();
  }

  @override
  void didUpdateWidget(covariant WebMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBob();
  }

  void _syncBob() {
    final hasTraveling = widget.birds.any((b) => b.isTraveling) || widget.friendsBirds.isNotEmpty;
    if (hasTraveling && !_bobController.isAnimating) {
      _bobController.repeat(reverse: true);
    } else if (!hasTraveling && _bobController.isAnimating) {
      _bobController.stop();
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  List<_MapFlight> _resolveFlights() {
    final nestsById = <String, Waypoint>{
      for (final n in [...widget.ownNests, ...widget.friendWaypoints]) n.id: n,
      for (final h in widget.hubs)
        h.id: Waypoint(id: h.id, userId: h.createdByUserId, name: h.name, latitude: h.latitude, longitude: h.longitude),
    };

    final result = <_MapFlight>[];
    for (final bird in widget.birds) {
      if (!bird.isTraveling || bird.departedAt == null || bird.estimatedArrivalAt == null) continue;
      final origin = nestsById[bird.nestFromId];
      final destination = nestsById[bird.nestToId];
      if (origin == null || destination == null) continue;
      result.add(_MapFlight(
        id: bird.id,
        color: Theme.of(context).colorScheme.primary,
        origin: origin,
        destination: destination,
        departedAt: bird.departedAt!,
        estimatedArrivalAt: bird.estimatedArrivalAt!,
        ownBird: bird,
      ));
    }
    for (final fb in widget.friendsBirds) {
      final origin = nestsById[fb.nestFromId];
      final destination = nestsById[fb.nestToId];
      if (origin == null || destination == null) continue;
      result.add(_MapFlight(
        id: fb.id,
        color: fb.color != null ? hexToColor(fb.color!) : CroColors.fog,
        origin: origin,
        destination: destination,
        departedAt: fb.departedAt,
        estimatedArrivalAt: fb.estimatedArrivalAt,
        ownBird: null,
        friendBird: fb,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final flights = _resolveFlights();
    final now = DateTime.now();
    final hasOwnNests = widget.ownNests.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: hasOwnNests ? LatLng(widget.ownNests.first.latitude, widget.ownNests.first.longitude) : _amesCenter,
            initialZoom: hasOwnNests ? 13 : 12,
            minZoom: 3,
            cameraConstraint: const CameraConstraint.containLatitude(),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onTap: widget.addingNest ? (tapPosition, point) => widget.onPlaceNest?.call(point) : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cro_app',
            ),
            if (flights.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final f in flights)
                    Polyline(
                      points: curvedFlightPathPoints(origin: f.origin, destination: f.destination),
                      color: f.color,
                      strokeWidth: 2.5,
                      pattern: StrokePattern.dashed(segments: const [8, 6]),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final hub in widget.hubs)
                    Marker(
                      key: Key('webHubMarker_${hub.id}'),
                      point: LatLng(hub.latitude, hub.longitude),
                      width: 180,
                      height: 60,
                      child: MapMarkerPill(
                        borderRadius: 14,
                        selected: widget.selectedHubId == hub.id,
                        selectionColor: CroColors.deliveryAmber,
                        onTap: () => widget.onSelectHub(hub),
                        avatar: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: CroColors.deliveryAmber, borderRadius: BorderRadius.circular(11)),
                          child: Text(
                            hub.name.isEmpty ? '?' : hub.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        name: hub.name,
                        subtitle: hub.category ?? 'Landmark',
                      ),
                    ),
                for (final nest in widget.ownNests)
                  Marker(
                    key: Key('webOwnNestMarker_${nest.id}'),
                    point: LatLng(nest.latitude, nest.longitude),
                    width: 180,
                    height: 60,
                    child: MapMarkerPill(
                      selected: widget.selectedNestId == nest.id,
                      selectionColor: CroColors.waypointBlue,
                      onTap: () => widget.onSelectNest(nest),
                      avatar: CircleAvatar(
                        radius: 19,
                        backgroundColor: CroColors.waypointBlue,
                        child: Text(
                          nest.name.isEmpty ? '?' : nest.name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      name: nest.name,
                      subtitle: '${widget.birds.where((b) => !b.isTraveling && b.currentNestId == nest.id).length} of yours here',
                    ),
                  ),
                for (final fw in widget.friendWaypoints)
                  Marker(
                    key: Key('webFriendNestMarker_${fw.id}'),
                    point: LatLng(fw.latitude, fw.longitude),
                    width: 180,
                    height: 60,
                    child: MapMarkerPill(
                      selected: widget.selectedNestId == fw.id,
                      selectionColor: hexToColor(fw.color ?? '#6B7280'),
                      onTap: () => widget.onSelectNest(fw),
                      avatar: CircleAvatar(
                        radius: 19,
                        backgroundColor: hexToColor(fw.color ?? '#6B7280'),
                        child: Text(
                          fw.name.isEmpty ? '?' : fw.name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: f.ownBird != null
                          ? () => widget.onSelectBird(f.ownBird!)
                          : (f.isPublicFriendBird ? () => widget.onSelectFriendBird(f.friendBird!) : null),
                      child: AnimatedBuilder(
                        animation: _bobController,
                        builder: (context, child) => Transform.translate(offset: Offset(0, -4 * _bobController.value), child: child),
                        child: _BirdMarkerDot(
                          key: Key('webBirdMarkerDot_${f.id}'),
                          color: f.color,
                          heading: bearingDegrees(
                            origin: f.origin,
                            destination: f.destination,
                            fraction: elapsedFraction(departedAt: f.departedAt, estimatedArrivalAt: f.estimatedArrivalAt, now: now),
                          ),
                          isPublic: f.isPublicFriendBird,
                          hasViewed: f.hasViewed,
                          selected: f.id == widget.selectedBirdId,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(color: CroColors.ink, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Click anywhere on the map to place your new nest',
                      style: TextStyle(fontSize: 12.5, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      key: const Key('webCancelAddNest'),
                      onTap: widget.onCancelAddNest,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: CroColors.skyTint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BirdMarkerDot extends StatelessWidget {
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
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 14, spreadRadius: 3)],
              ),
            ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x4D2B2F33), blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
          AnimatedRotation(
            turns: heading / 360,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: const Icon(Icons.arrow_drop_up, size: 16, color: Colors.white),
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
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Text(
                  '!',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
                ),
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
