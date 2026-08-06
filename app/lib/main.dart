import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_state.dart';

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
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          return authState.isLoggedIn
              ? HomeScreen(authState: authState)
              : LoginScreen(authState: authState);
        },
      ),
    );
  }
}
