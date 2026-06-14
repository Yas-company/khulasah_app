import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for providing haptic and audio feedback throughout the app.
///
/// Provides a premium feel with subtle haptics and optional sounds.
class AppFeedbackService {
  static AppFeedbackService? _instance;

  AudioPlayer? _audioPlayer;
  bool _soundEnabled = true;
  bool _hapticsEnabled = true;
  bool _isInitialized = false;

  AppFeedbackService._();

  static AppFeedbackService get instance {
    _instance ??= AppFeedbackService._();
    return _instance!;
  }

  /// Initialize the service and load preferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setVolume(0.3); // Soft volume
      await _loadPreferences();
      _isInitialized = true;
      debugPrint('[Feedback] Service initialized');
      debugPrint('[Feedback] Sound enabled: $_soundEnabled');
      debugPrint('[Feedback] Haptics enabled: $_hapticsEnabled');
    } catch (e) {
      debugPrint('[Feedback] Failed to initialize: $e');
    }
  }

  /// Load saved preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool('soundEnabled') ?? true;
      _hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
    } catch (e) {
      debugPrint('[Feedback] Failed to load preferences: $e');
    }
  }

  /// Save sound preference
  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    debugPrint('[Feedback] Sound enabled: $enabled');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('soundEnabled', enabled);
    } catch (e) {
      debugPrint('[Feedback] Failed to save sound preference: $e');
    }
  }

  /// Save haptics preference
  Future<void> setHapticsEnabled(bool enabled) async {
    _hapticsEnabled = enabled;
    debugPrint('[Feedback] Haptics enabled: $enabled');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hapticsEnabled', enabled);
    } catch (e) {
      debugPrint('[Feedback] Failed to save haptics preference: $e');
    }
  }

  /// Get current sound enabled state
  bool get soundEnabled => _soundEnabled;

  /// Get current haptics enabled state
  bool get hapticsEnabled => _hapticsEnabled;

  /// Light tap feedback for normal button presses
  Future<void> tap() async {
    debugPrint('[Feedback] Tap triggered');

    if (_hapticsEnabled) {
      try {
        await HapticFeedback.lightImpact();
      } catch (e) {
        debugPrint('[Feedback] Haptic tap failed: $e');
      }
    }

    if (_soundEnabled) {
      _playSound('tap.mp3');
    }
  }

  /// Selection feedback for toggles, checkboxes, options
  Future<void> selection() async {
    debugPrint('[Feedback] Selection triggered');

    if (_hapticsEnabled) {
      try {
        await HapticFeedback.selectionClick();
      } catch (e) {
        debugPrint('[Feedback] Haptic selection failed: $e');
      }
    }
  }

  /// Success feedback for completed actions
  Future<void> success() async {
    debugPrint('[Feedback] Success triggered');

    if (_hapticsEnabled) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (e) {
        debugPrint('[Feedback] Haptic success failed: $e');
      }
    }

    if (_soundEnabled) {
      _playSound('success.mp3');
    }
  }

  /// Error feedback for failed actions
  Future<void> error() async {
    debugPrint('[Feedback] Error triggered');

    if (_hapticsEnabled) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (e) {
        // Fallback to vibrate if heavy impact not supported
        try {
          await HapticFeedback.vibrate();
        } catch (_) {
          debugPrint('[Feedback] Haptic error failed');
        }
      }
    }

    if (_soundEnabled) {
      _playSound('error.mp3');
    }
  }

  /// Play a sound file from assets
  Future<void> _playSound(String fileName) async {
    if (_audioPlayer == null || !_soundEnabled) return;

    try {
      await _audioPlayer!.stop();
      await _audioPlayer!.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      debugPrint('[Feedback] Failed to play sound $fileName: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _isInitialized = false;
  }
}
