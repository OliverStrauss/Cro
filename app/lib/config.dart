// Note: on an Android emulator, `localhost` refers to the emulator itself, not the
// host machine - use 10.0.2.2 instead. Not handled here since no platform target is
// confirmed yet; revisit once the app actually runs on an Android emulator.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5287',
);
