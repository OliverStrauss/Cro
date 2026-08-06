import 'package:flutter/foundation.dart';

class AuthState extends ChangeNotifier {
  String? _token;

  bool get isLoggedIn => _token != null;
  String? get token => _token;

  void login(String token) {
    _token = token;
    notifyListeners();
  }

  void logout() {
    _token = null;
    notifyListeners();
  }
}
