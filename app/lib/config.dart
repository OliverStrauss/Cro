const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

String get apiBaseUrl =>
    _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : 'http://localhost:5287';
