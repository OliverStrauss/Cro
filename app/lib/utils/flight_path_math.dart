import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/waypoint.dart';

// Pure flight-path math for web_map_screen.dart. Every function here only ever reads a
// Waypoint's .latitude/.longitude/.name, so a Hub can be (and is) projected into a
// Waypoint-shaped record to reuse this without a Hub-vs-Waypoint union type anywhere.

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
// same EPSG3857 projected space, then unprojected back to LatLng, so the curve matches how
// flutter_map itself projects the map.
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
