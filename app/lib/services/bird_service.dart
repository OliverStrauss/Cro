import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/bird.dart';

class BirdException implements Exception {
  final String message;
  BirdException(this.message);

  @override
  String toString() => message;
}

class BirdService {
  Future<List<Bird>> listBirds(String token) async {
    final response = await _get('/birds', token, 'Could not load birds');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Bird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Bird>> getNestResidents(String token, String nestId) async {
    final response =
        await _get('/waypoints/$nestId/birds', token, "Could not load this nest's birds");
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Bird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Bird> sendBird(String token, String birdId, {required String nestId, String? content}) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/birds/$birdId/send'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'nestId': nestId, 'content': content}),
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not send this bird'));
    }
    return Bird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Bird> markBirdRead(String token, String birdId) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/birds/$birdId/read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not mark this bird as read'));
    }
    return Bird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _get(String path, String token, String errorFallback) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, errorFallback));
    }
    return response;
  }

  // Bird error responses are {"error": "..."} - same pattern as WaypointService.
  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
