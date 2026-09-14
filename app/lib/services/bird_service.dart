import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_client.dart' as api;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/bird.dart';
import '../models/public_bird.dart';

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

  // Any user's public, currently-in-flight birds - not scoped to friends at all, unlike
  // FriendsService.getFriendsBirds. Lives here rather than FriendsService precisely because
  // it isn't a friends concept.
  Future<List<PublicBird>> getPublicBirds(String token) async {
    final response = await _get('/birds/public', token, 'Could not load public birds');
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => PublicBird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Bird>> getNestResidents(String token, String nestId) async {
    final response =
        await _get('/waypoints/$nestId/birds', token, "Could not load this nest's birds");
    return (jsonDecode(response.body) as List<dynamic>)
        .map((e) => Bird.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // mediaBytes/mediaContentType/mediaFilename carry this leg's payload for a Parrot (audio)
  // or Pigeon/Raven (image) - a bird's Type fixes what it can carry, enforced server-side by
  // BirdPayloadValidator.ValidateAllowed.
  Future<Bird> sendBird(
    String token,
    String birdId, {
    required String nestId,
    String? content,
    bool isPublic = false,
    List<int>? mediaBytes,
    String? mediaContentType,
    String? mediaFilename,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/birds/$birdId/send'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['nestId'] = nestId
      ..fields['isPublic'] = isPublic.toString();
    if (content != null) {
      request.fields['content'] = content;
    }
    if (mediaBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        mediaBytes,
        filename: mediaFilename ?? 'media',
        contentType: mediaContentType != null ? MediaType.parse(mediaContentType) : null,
      ));
    }

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await api.send(request);
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not send this bird'));
    }
    return Bird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Bird> renameBird(String token, String birdId, String name) async {
    final http.Response response;
    try {
      response = await api.put(
        Uri.parse('$apiBaseUrl/birds/$birdId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name}),
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not rename this bird'));
    }
    return Bird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // Only succeeds once the bird is idle at the caller's private nest - the server enforces
  // this and returns a 409 with an explanatory message otherwise.
  Future<void> deleteBird(String token, String birdId) async {
    final http.Response response;
    try {
      response = await api.delete(
        Uri.parse('$apiBaseUrl/birds/$birdId'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw BirdException(_errorMessage(response, 'Could not delete this bird'));
    }
  }

  // Wrapped here (rather than called directly from the widgets that use it) so the
  // pick-then-upload flow can be faked as a unit in tests - image_picker's platform channel
  // isn't available in the widget test harness. Same pattern as ProfileService.pickImage.
  Future<XFile?> pickImage() => ImagePicker().pickImage(source: ImageSource.gallery);

  // A bird's own avatar - distinct from the payload media (audio/image) a specific message
  // carries, same split as uploadWaypointPicture vs. a nest's residents.
  Future<String> uploadBirdPicture(
    String token,
    String birdId,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$apiBaseUrl/birds/$birdId/picture'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await api.send(request);
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not upload bird picture'));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['profilePictureUrl'] as String;
  }

  Future<Bird> markBirdRead(String token, String birdId) async {
    final http.Response response;
    try {
      response = await api.post(
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

  // Distinct from markBirdRead above: that one is the *owner* marking their own delivered
  // bird read. This is any friend marking a public bird (theirs or someone else's) viewed -
  // clears that bird's "unread" badge on the map on the next refresh. Only public birds can
  // be marked this way; the server rejects a private one.
  Future<void> markBirdViewed(String token, String birdId) async {
    final http.Response response;
    try {
      response = await api.post(
        Uri.parse('$apiBaseUrl/birds/$birdId/viewed'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 204) {
      throw BirdException(_errorMessage(response, 'Could not mark this bird as viewed'));
    }
  }

  // Sends a bird someone else delivered to the caller's own nest back to its owner's home -
  // same "delivered, resident at a nest I own" gate the server enforces for pinning.
  Future<Bird> shooBird(String token, String birdId) async {
    final http.Response response;
    try {
      response = await api.post(
        Uri.parse('$apiBaseUrl/birds/$birdId/shoo'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw BirdException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw BirdException(_errorMessage(response, 'Could not shoo this bird home'));
    }
    return Bird.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _get(String path, String token, String errorFallback) async {
    final http.Response response;
    try {
      response = await api.get(
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
