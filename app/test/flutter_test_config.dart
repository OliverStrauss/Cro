import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

// Recognized by `flutter test` automatically for every test file under this directory -
// AuthState reads/writes shared_preferences on construction/login/logout, which throws
// MissingPluginException in a plain widget test unless the plugin's mock store is seeded
// first. One config file here covers every test, instead of repeating this in each of them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
