import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/waypoint.dart';

class WaypointException implements Exception {
  final String message;
  WaypointException(this.message);

  @override
  String toString() => message;
}

class WaypointService {
  Future<List<Waypoint>> listWaypoints(String token) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/waypoints'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw WaypointException(_errorMessage(response, 'Could not load nests'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Waypoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Waypoint> createWaypoint(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/waypoints'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name, 'latitude': latitude, 'longitude': longitude}),
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode != 201) {
      throw WaypointException(_errorMessage(response, 'Could not create nest'));
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Waypoint> updateWaypoint(
    String token,
    String id, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final http.Response response;
    try {
      response = await http.put(
        Uri.parse('$apiBaseUrl/waypoints/$id'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name, 'latitude': latitude, 'longitude': longitude}),
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw WaypointException(_errorMessage(response, 'Could not update nest'));
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteWaypoint(String token, String id) async {
    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$apiBaseUrl/waypoints/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw WaypointException(_errorMessage(response, 'Could not delete nest'));
    }
  }

  // Waypoint error responses are {"error": "..."} - surface that message when present
  // (e.g. the 5-nest cap) rather than a generic one, same pattern as FriendsService.
  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
