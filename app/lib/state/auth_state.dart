import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState extends ChangeNotifier {
  static const _tokenKey = 'auth_token';

  String? _token;

  // Restores a previously persisted session on construction, so a browser refresh (which
  // recreates AuthState from scratch on web) doesn't force the user back to the login
  // screen. Fire-and-forget: the app renders immediately with whatever _token already is
  // (null, unless SKIP_LOGIN set it), then rebuilds once restore completes if it finds one.
  AuthState() {
    _restoreToken();
  }

  Future<void> _restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tokenKey);
    // Only apply if nothing has logged in/out in the meantime - avoids clobbering a token
    // set synchronously (e.g. SKIP_LOGIN, or a real login) while this restore was pending.
    if (stored != null && _token == null) {
      _token = stored;
      notifyListeners();
    }
  }

  bool get isLoggedIn => _token != null;
  String? get token => _token;

  Future<void> login(String token) async {
    _token = token;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> logout() async {
    _token = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
