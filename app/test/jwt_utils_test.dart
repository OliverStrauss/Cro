import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/utils/jwt_utils.dart';

// Builds a syntactically valid (unsigned) JWT for testing - the client never verifies
// the signature itself, so a real one isn't needed here.
String _fakeJwt(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  final header = segment({'alg': 'HS256', 'typ': 'JWT'});
  final body = segment(payload);
  return '$header.$body.fake-signature';
}

void main() {
  test('jwtSubject extracts the sub claim', () {
    final token = _fakeJwt({'sub': 'user-123', 'unique_name': 'alice'});

    expect(jwtSubject(token), 'user-123');
  });

  test('decodeJwtPayload returns the full payload map', () {
    final token = _fakeJwt({'sub': 'user-123', 'unique_name': 'alice'});

    final payload = decodeJwtPayload(token);

    expect(payload['sub'], 'user-123');
    expect(payload['unique_name'], 'alice');
  });

  test('throws a FormatException for a malformed token', () {
    expect(() => decodeJwtPayload('not-a-jwt'), throwsFormatException);
  });
}
