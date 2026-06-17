import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of text recognition from an image
class OcrResult {
  final String? text;
  final bool success;
  final String? errorMessage;

  const OcrResult._({
    this.text,
    required this.success,
    this.errorMessage,
  });

  factory OcrResult.success(String text) {
    return OcrResult._(text: text, success: true);
  }

  factory OcrResult.failure(String message) {
    return OcrResult._(success: false, errorMessage: message);
  }

  factory OcrResult.unavailable() {
    return const OcrResult._(
      success: false,
      errorMessage: 'Text recognition unavailable on this device',
    );
  }

  bool get hasText => text != null && text!.isNotEmpty;
}

/// Service for on-device text recognition using platform-native APIs.
/// Uses Apple Vision on iOS for text extraction from images.
/// This is an internal service - never expose technical details to users.
class OcrService {
  static OcrService? _instance;
  static const MethodChannel _channel = MethodChannel('com.khulasah.ocr/vision');

  OcrService._();

  static OcrService get instance {
    _instance ??= OcrService._();
    return _instance!;
  }

  /// Check if text recognition is available on this device
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('[OCR] Availability check failed: $e');
      return false;
    }
  }

  /// Recognize text from image bytes
  /// Returns recognized text or empty result if recognition fails
  Future<OcrResult> recognizeText(Uint8List imageBytes) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'recognizeText',
        {'imageBytes': imageBytes},
      );

      if (result != null && result.isNotEmpty) {
        debugPrint('[OCR] Recognized ${result.length} chars');
        return OcrResult.success(result);
      } else {
        debugPrint('[OCR] No text recognized from image');
        return OcrResult.success('');
      }
    } on PlatformException catch (e) {
      debugPrint('[OCR] Platform exception: ${e.message}');
      return OcrResult.failure(e.message ?? 'Recognition failed');
    } on MissingPluginException {
      debugPrint('[OCR] OCR unavailable: Plugin not registered');
      return OcrResult.unavailable();
    } catch (e) {
      debugPrint('[OCR] Recognition error: $e');
      return OcrResult.failure(e.toString());
    }
  }

  /// Recognize text from PDF pages using native PDFKit + Vision
  /// This is the preferred method for OCR fallback as it handles
  /// PDF rendering natively on iOS for better compatibility.
  ///
  /// [filePath] - Full path to the PDF file
  /// [fromPage] - Start page (1-indexed)
  /// [toPage] - End page (1-indexed)
  Future<OcrResult> recognizeTextFromPdfPages({
    required String filePath,
    required int fromPage,
    required int toPage,
  }) async {
    debugPrint('[OCR] Calling native PDF OCR: pages $fromPage-$toPage');
    debugPrint('[OCR] File path: $filePath');

    try {
      final result = await _channel.invokeMethod<String>(
        'recognizeTextFromPdfPages',
        {
          'filePath': filePath,
          'fromPage': fromPage,
          'toPage': toPage,
        },
      );

      if (result != null && result.isNotEmpty) {
        debugPrint('[OCR] Native OCR returned ${result.length} chars');
        return OcrResult.success(result);
      } else {
        debugPrint('[OCR] Native OCR returned no text');
        return OcrResult.success('');
      }
    } on PlatformException catch (e) {
      debugPrint('[OCR] Native OCR platform exception: ${e.code} - ${e.message}');
      if (e.code == 'PDF_OPEN_FAILED') {
        return OcrResult.failure('Could not open PDF for processing');
      }
      return OcrResult.failure(e.message ?? 'OCR failed');
    } on MissingPluginException {
      debugPrint('[OCR] Native OCR unavailable: Plugin not registered');
      return OcrResult.unavailable();
    } catch (e) {
      debugPrint('[OCR] Native OCR error: $e');
      return OcrResult.failure(e.toString());
    }
  }
}
