import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/bird_reaction.dart';

class BirdReactionException implements Exception {
  final String message;
  BirdReactionException(this.message);

  @override
  String toString() => message;
}

class BirdReactionService {
  Future<List<BirdReactionSummary>> getReactions(String token, String birdId) async {
    final response = await _send(http.Request('GET', Uri.parse('$apiBaseUrl/birds/$birdId/reactions')), token);
    if (response.statusCode != 200) {
      throw BirdReactionException(_errorMessage(response, 'Could not load reactions'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => BirdReactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BirdReactionSummary>> addReaction(String token, String birdId, String emoji) async {
    final response = await _send(
      http.Request('PUT', Uri.parse('$apiBaseUrl/birds/$birdId/reactions/${Uri.encodeComponent(emoji)}')),
      token,
    );
    if (response.statusCode != 200) {
      throw BirdReactionException(_errorMessage(response, 'Could not add reaction'));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => BirdReactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeReaction(String token, String birdId, String emoji) async {
    final response = await _send(
      http.Request('DELETE', Uri.parse('$apiBaseUrl/birds/$birdId/reactions/${Uri.encodeComponent(emoji)}')),
      token,
    );
    if (response.statusCode != 204) {
      throw BirdReactionException(_errorMessage(response, 'Could not remove reaction'));
    }
  }

  Future<http.Response> _send(http.Request request, String token) async {
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await request.send();
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw BirdReactionException('Could not reach the server');
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
