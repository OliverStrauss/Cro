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
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/birds'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not load birds'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Bird.fromJson(e as Map<String, dynamic>))
        .toList();
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
