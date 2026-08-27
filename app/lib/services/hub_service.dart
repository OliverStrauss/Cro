import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/hub.dart';
import '../models/hub_message.dart';

class HubException implements Exception {
  final String message;
  HubException(this.message);

  @override
  String toString() => message;
}

class HubService {
  Future<List<Hub>> listHubs(String token) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/hubs'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw HubException(_errorMessage(response, 'Could not load hubs'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Hub.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Only ever succeeds for an admin caller - the server returns 403 otherwise. The map
  // screen only exposes the UI to call this when the signed-in user is already known to
  // be an admin, but the server-side check is the one that actually matters.
  Future<Hub> createHub(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
    String? category,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/hubs'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'category': category,
        }),
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 201) {
      throw HubException(_errorMessage(response, 'Could not create hub'));
    }
    return Hub.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // The Hub's message board - durable history of everything that's ever landed there,
  // newest first, unlike the live "who's currently here" residents endpoint.
  Future<List<HubMessage>> listMessages(String token, String hubId) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/hubs/$hubId/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw HubException(_errorMessage(response, 'Could not load messages'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => HubMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
