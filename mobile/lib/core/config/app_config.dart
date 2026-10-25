import 'package:flutter/foundation.dart';

/// Build-time configuration, passed with `--dart-define`.
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5050
///
/// Only non-secret values belong here. Server secrets (JWT, database,
/// Cloudinary, SMTP) stay on the backend.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  /// Origin of the EMSTRAP backend. REST and Socket.IO share it.
  final String apiBaseUrl;

  static const _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Debug-only fallback: the Android emulator's alias for the developer
  /// machine, where the backend runs locally on port 5050.
  static const _debugFallbackBaseUrl = 'http://10.0.2.2:5050';

  static AppConfig fromEnvironment() {
    final url = _definedBaseUrl.isNotEmpty
        ? _definedBaseUrl
        : (kDebugMode ? _debugFallbackBaseUrl : '');
    if (url.isEmpty) {
      throw StateError(
        'API_BASE_URL is not set. Build with --dart-define=API_BASE_URL=https://…',
      );
    }
    return AppConfig(apiBaseUrl: url.replaceAll(RegExp(r'/+$'), ''));
  }
}
