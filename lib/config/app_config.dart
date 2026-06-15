import 'package:flutter/foundation.dart';

/// App configuration for different build modes.
///
/// - Debug: Uses local Node.js backend (http://127.0.0.1:3000)
/// - Release: Uses Cloudflare Worker (https://khulasah-worker.mhmdajoor5.workers.dev)
class AppConfig {
  AppConfig._();

  /// Local backend URL for debug mode (iOS Simulator)
  static const String _localBackendUrl = 'http://127.0.0.1:3000';

  /// Production backend URL (Cloudflare Worker)
  static const String _productionBackendUrl =
      'https://khulasah-worker.mhmdajoor5.workers.dev';

  /// Get the appropriate backend URL based on build mode
  static String get backendUrl {
    if (kDebugMode) {
      debugPrint('[AppConfig] Using local backend: $_localBackendUrl');
      return _localBackendUrl;
    } else {
      debugPrint('[AppConfig] Using production backend: $_productionBackendUrl');
      return _productionBackendUrl;
    }
  }

  /// Whether the app is running in debug mode
  static bool get isDebug => kDebugMode;

  /// Whether the app is running in release mode
  static bool get isRelease => kReleaseMode;
}
