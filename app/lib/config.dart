import 'package:flutter/foundation.dart';

const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

// Android emulator's `localhost` refers to the emulator itself, not the host
// machine - 10.0.2.2 is the emulator's special alias back to the host. A physical
// device needs the host's real LAN IP instead; pass --dart-define=API_BASE_URL=...
// to override this default in that case.
String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) {
    return _apiBaseUrlOverride;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:5287';
  }
  return 'http://localhost:5287';
}
