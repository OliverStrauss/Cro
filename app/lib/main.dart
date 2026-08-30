import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_state.dart';
import 'theme.dart';
import 'web/screens/web_shell_screen.dart';

// Manual-dev-testing convenience only (not used by the automated test suite):
// `flutter run --dart-define=SKIP_LOGIN=true` jumps straight past the login screen.
const bool skipLogin = bool.fromEnvironment('SKIP_LOGIN', defaultValue: false);

void main() {
  final authState = AuthState();
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
          // The web shell is a full sibling replacement for the phone's three-tab
          // HomeScreen, not a responsive variant of it - every other platform keeps the
          // phone shell completely unchanged.
          return kIsWeb ? WebShellScreen(authState: authState) : HomeScreen(authState: authState);
        },
      ),
    );
  }
}
