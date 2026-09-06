import 'package:http/http.dart' as http;

// Every service call flows through the functions below instead of package:http's
// top-level get/post/put/delete/send directly, so a 401 (expired or invalid token) is
// handled once, centrally, instead of needing a check after each of the ~40 call sites
// across the service layer. main.dart wires [onUnauthorized] to clear AuthState.
void Function()? onUnauthorized;

void _checkUnauthorized(int statusCode) {
  if (statusCode == 401) {
    onUnauthorized?.call();
  }
}

Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
  final response = await http.get(url, headers: headers);
  _checkUnauthorized(response.statusCode);
  return response;
}

Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body}) async {
  final response = await http.post(url, headers: headers, body: body);
  _checkUnauthorized(response.statusCode);
  return response;
}

Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body}) async {
  final response = await http.put(url, headers: headers, body: body);
  _checkUnauthorized(response.statusCode);
  return response;
}

Future<http.Response> delete(Uri url, {Map<String, String>? headers}) async {
  final response = await http.delete(url, headers: headers);
  _checkUnauthorized(response.statusCode);
  return response;
}

Future<http.StreamedResponse> send(http.BaseRequest request) async {
  final response = await request.send();
  _checkUnauthorized(response.statusCode);
  return response;
}
