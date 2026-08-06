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
  Future<Waypoint?> getWaypoint(String token) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/waypoint'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw WaypointException('Could not load waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Waypoint> saveWaypoint(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final http.Response response;
    try {
      response = await http.put(
        Uri.parse('$apiBaseUrl/waypoint'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name, 'latitude': latitude, 'longitude': longitude}),
      );
    } catch (_) {
      throw WaypointException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw WaypointException('Could not save waypoint');
    }
    return Waypoint.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
