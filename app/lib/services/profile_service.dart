import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/user_profile.dart';

class ProfileException implements Exception {
  final String message;
  ProfileException(this.message);

  @override
  String toString() => message;
}

class ProfileService {
  Future<UserProfile> getUser(String userId) async {
    final http.Response response;
    try {
      response = await http.get(Uri.parse('$apiBaseUrl/users/$userId'));
    } catch (_) {
      throw ProfileException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw ProfileException('Could not load profile');
    }
    return UserProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // Wrapped here (rather than called directly from ProfileScreen) so the whole
  // pick-then-upload flow can be faked as a unit in tests, the same injectable-service
  // pattern used everywhere else in this app - image_picker's platform channel isn't
  // available in the widget test harness.
  Future<XFile?> pickImage() => ImagePicker().pickImage(source: ImageSource.gallery);

  Future<String> uploadProfilePicture(
    String token,
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$apiBaseUrl/profile/picture'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request.send();
    } catch (_) {
      throw ProfileException('Could not reach the server');
    }

    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw ProfileException('Could not upload profile picture');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['profilePictureUrl'] as String;
  }
}
