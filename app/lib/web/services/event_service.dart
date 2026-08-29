import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config.dart';
import '../models/event.dart';

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}

class EventService {
  Future<List<AppEvent>> listEvents(String token, {int limit = 200}) async {
    final response = await _send(
      http.Request('GET', Uri.parse('$apiBaseUrl/events?limit=$limit')),
      token,
    );
    if (response.statusCode != 200) {
      throw EventException(_errorMessage(response, 'Could not load the journey log'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => AppEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppEvent>> listNotifications(String token, {int limit = 50}) async {
    final response = await _send(
      http.Request('GET', Uri.parse('$apiBaseUrl/notifications?limit=$limit')),
      token,
    );
    if (response.statusCode != 200) {
      throw EventException(_errorMessage(response, 'Could not load notifications'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => AppEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> getUnreadCount(String token) async {
    final response = await _send(
      http.Request('GET', Uri.parse('$apiBaseUrl/notifications/unread-count')),
      token,
    );
    if (response.statusCode != 200) {
      throw EventException(_errorMessage(response, 'Could not load the unread count'));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['count'] as int;
  }

  Future<void> markNotificationRead(String token, String eventId) async {
    final response = await _send(
      http.Request('POST', Uri.parse('$apiBaseUrl/notifications/$eventId/read')),
      token,
    );
    if (response.statusCode != 204) {
      throw EventException(_errorMessage(response, 'Could not mark that notification read'));
    }
  }

  Future<void> markAllNotificationsRead(String token) async {
    final response = await _send(
      http.Request('POST', Uri.parse('$apiBaseUrl/notifications/read-all')),
      token,
    );
    if (response.statusCode != 204) {
      throw EventException(_errorMessage(response, 'Could not mark notifications read'));
    }
  }

  Future<http.Response> _send(http.Request request, String token) async {
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await request.send();
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw EventException('Could not reach the server');
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
