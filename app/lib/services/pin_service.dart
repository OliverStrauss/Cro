import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/pinned_bird.dart';
import 'api_client.dart' as api;

class PinException implements Exception {
  final String message;
  PinException(this.message);

  @override
  String toString() => message;
}

class PinService {
  Future<PinnedBird> pinBird(String token, String birdId) async {
    final response = await _send(http.Request('POST', Uri.parse('$apiBaseUrl/birds/$birdId/pin')), token);
    if (response.statusCode != 200) {
      throw PinException(_errorMessage(response, 'Could not pin this bird'));
    }
    return PinnedBird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> unpinBird(String token, String pinId) async {
    final response = await _send(http.Request('DELETE', Uri.parse('$apiBaseUrl/pins/$pinId')), token);
    if (response.statusCode != 204) {
      throw PinException(_errorMessage(response, 'Could not unpin this message'));
    }
  }

  Future<List<PinnedBird>> listMyPins(String token) async {
    final response = await _send(http.Request('GET', Uri.parse('$apiBaseUrl/pins/mine')), token);
    if (response.statusCode != 200) {
      throw PinException(_errorMessage(response, 'Could not load your pinned messages'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => PinnedBird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PinnedBird>> listPublicPins(String token) async {
    final response = await _send(http.Request('GET', Uri.parse('$apiBaseUrl/pins/public')), token);
    if (response.statusCode != 200) {
      throw PinException(_errorMessage(response, 'Could not load the public pinned feed'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => PinnedBird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<http.Response> _send(http.Request request, String token) async {
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await api.send(request);
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw PinException('Could not reach the server');
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
