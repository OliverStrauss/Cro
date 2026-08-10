import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/friend.dart';
import '../models/friend_bird.dart';
import '../models/friend_request.dart';
import '../models/waypoint.dart';

class FriendsException implements Exception {
  final String message;
  FriendsException(this.message);

  @override
  String toString() => message;
}

class FriendsService {
  Future<List<Friend>> getFriends(String token) async {
    final response = await _get('/friends', token, 'Could not load friends');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendRequest>> getIncomingRequests(String token) async {
    final response =
        await _get('/friends/requests/incoming', token, 'Could not load friend requests');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendRequest>> getOutgoingRequests(String token) async {
    final response =
        await _get('/friends/requests/outgoing', token, 'Could not load friend requests');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendFriendRequest(String token, String username) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/friends/requests'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'username': username}),
      );
    } catch (_) {
      throw FriendsException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw FriendsException(_errorMessage(response, 'Could not send friend request'));
    }
  }

  Future<void> acceptFriendRequest(String token, String requesterId) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/friends/requests/$requesterId/accept'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw FriendsException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw FriendsException(_errorMessage(response, 'Could not accept friend request'));
    }
  }

  Future<void> removeFriend(String token, String userId) async {
    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$apiBaseUrl/friends/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw FriendsException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw FriendsException(_errorMessage(response, 'Could not remove friend'));
    }
  }

  Future<List<Waypoint>> getFriendsWaypoints(String token) async {
    final response =
        await _get('/friends/waypoints', token, "Could not load friends' waypoints");
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Waypoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendBird>> getFriendsBirds(String token) async {
    final response = await _get('/friends/birds', token, "Could not load friends' birds");
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => FriendBird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setFriendColor(String token, String friendId, String color) async {
    final http.Response response;
    try {
      response = await http.put(
        Uri.parse('$apiBaseUrl/friends/$friendId/color'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'color': color}),
      );
    } catch (_) {
      throw FriendsException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw FriendsException(_errorMessage(response, 'Could not update color'));
    }
  }

  Future<http.Response> _get(String path, String token, String errorFallback) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$apiBaseUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw FriendsException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw FriendsException(_errorMessage(response, errorFallback));
    }
    return response;
  }

  // Friend-service error responses are {"error": "..."} - surface that message when
  // present rather than a generic one, since it's specific enough to act on (e.g.
  // "No user with that username").
  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
