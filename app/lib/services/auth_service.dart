import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart' as api;

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
      response = await api.post(
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

  Future<void> signUp(String username, String email, String password) async {
    final http.Response response;
    try {
      response = await api.post(
        Uri.parse('$apiBaseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'email': email, 'password': password}),
      );
    } catch (_) {
      throw AuthException('Could not reach the server');
    }

    if (response.statusCode == 409) {
      throw AuthException('That username is already taken');
    }
    if (response.statusCode != 201) {
      throw AuthException('Could not create account');
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await api.post(
        Uri.parse('$apiBaseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
    } catch (_) {
      throw AuthException('Could not reach the server');
    }
  }

  Future<void> resetPassword(String email, String code, String newPassword) async {
    final http.Response response;
    try {
      response = await api.post(
        Uri.parse('$apiBaseUrl/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
      );
    } catch (_) {
      throw AuthException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw AuthException('Invalid or expired code');
    }
  }
}
