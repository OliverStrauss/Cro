import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/api_client.dart' as api_client;
import 'state/auth_state.dart';
import 'theme.dart';
import 'web/screens/web_shell_screen.dart';

// Manual-dev-testing convenience only (not used by the automated test suite):
// `flutter run --dart-define=SKIP_LOGIN=true` jumps straight past the login screen.
const bool skipLogin = bool.fromEnvironment('SKIP_LOGIN', defaultValue: false);

void main() {
  final authState = AuthState();
  // A 401 from any API call means the token expired or was revoked - log out centrally
  // rather than leaving the caller to fail silently or show a confusing error.
  api_client.onUnauthorized = authState.logout;
  if (skipLogin) {
    authState.login('dev-skip-login-token');
  }
  runApp(MyApp(authState: authState));
}

class MyApp extends StatelessWidget {
  final AuthState authState;

  const MyApp({super.key, required this.authState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cro',
      theme: croTheme,
      home: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          if (!authState.isLoggedIn) {
            return LoginScreen(authState: authState);
          }
          return WebShellScreen(authState: authState);
        },
      ),
    );
  }
}
