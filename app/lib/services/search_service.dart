import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_client.dart' as api;

import '../config.dart';
import '../models/search_results.dart';

class SearchException implements Exception {
  final String message;
  SearchException(this.message);

  @override
  String toString() => message;
}

class SearchService {
  // Powers the web shell's search trigger next to the notification bell - GET /search?q=,
  // same shape as FriendsService.searchUsers.
  Future<SearchResults> search(String token, String query) async {
    final http.Response response;
    try {
      response = await api.get(
        Uri.parse('$apiBaseUrl/search').replace(queryParameters: {'q': query}),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      throw SearchException('Could not reach the server');
    }

    if (response.statusCode != 200) {
      throw SearchException('Could not search');
    }
    return SearchResults.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
