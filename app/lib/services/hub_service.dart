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

  // Powers the unread-count badge under each Hub marker on the map - one round trip for
  // every hub the caller can see, keyed by hubId.
  Future<Map<String, int>> getUnreadCounts(String token) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/hubs/unread-counts'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw HubException(_errorMessage(response, 'Could not load unread counts'));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, value as int));
  }

  // Called when a Hub's board is opened - clears that hub's badge on the next refresh.
  Future<void> markHubRead(String token, String hubId) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/hubs/$hubId/read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw HubException(_errorMessage(response, 'Could not mark hub read'));
    }
  }

  // Any authenticated user can suggest a Hub location - the server enforces no admin gate
  // here, unlike createHub above.
  Future<Hub> suggestHub(
    String token, {
    required String name,
    required double latitude,
    required double longitude,
    String? category,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/hub-suggestions'),
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
      throw HubException(_errorMessage(response, 'Could not suggest hub'));
    }
    return Hub.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // Admin-only moderation feed - the server returns 403 for a non-admin caller.
  Future<List<Hub>> listSuggestions(String token) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl/hub-suggestions'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw HubException(_errorMessage(response, 'Could not load suggestions'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Hub.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Hub> approveSuggestion(String token, String hubId) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/hub-suggestions/$hubId/approve'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw HubException(_errorMessage(response, 'Could not approve suggestion'));
    }
    return Hub.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> rejectSuggestion(String token, String hubId) async {
    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$apiBaseUrl/hub-suggestions/$hubId'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw HubException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw HubException(_errorMessage(response, 'Could not reject suggestion'));
    }
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
