import 'dart:convert';

// No JWT library dependency needed for this - just base64url-decoding the payload
// segment. Signature verification is the server's job; the client only ever reads
// claims from a token it already trusts (one it just got back from /login).
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const FormatException('Not a valid JWT');
  }

  final normalized = base64Url.normalize(parts[1]);
  final decoded = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(decoded) as Map<String, dynamic>;
}

String? jwtSubject(String token) => decodeJwtPayload(token)['sub'] as String?;
