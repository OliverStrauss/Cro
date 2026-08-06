import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  Future<String> login(String username, String password) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (_) {
      throw AuthException('Could not reach the server');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['token'] as String;
    }

    throw AuthException('Invalid username or password');
  }
}
