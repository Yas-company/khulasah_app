import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Quality level of extracted text (internal rating only - never shown to user)
enum TextQuality {
  /// High quality - good readable ratio (>70%)
  high,
  /// Medium quality - acceptable but not perfect (40-70%)
  medium,
  /// Low quality - poor but still usable (<40%)
  low,
  /// Empty - no text found at all
  empty,
}

/// Content source for AI processing
enum ContentSource {
  /// Text was extracted from PDF
  extractedText,
  /// No content available
  empty,
  // TODO: Future content sources
  // visualPages - PDF pages rendered as images for vision AI
  // ocrText - Text extracted via OCR from scanned PDFs
  // directFile - PDF sent directly to AI that supports file processing
}

class PdfExtractionResult {
  final String? text;
  final String? originalText;
  final String? errorMessage;
  final bool success;
  final TextQuality quality;
  final double readableRatio;
  final ContentSource contentSource;

  const PdfExtractionResult._({
    this.text,
    this.originalText,
    this.errorMessage,
    required this.success,
    this.quality = TextQuality.high,
    this.readableRatio = 1.0,
    this.contentSource = ContentSource.extractedText,
  });

  factory PdfExtractionResult.success({
    required String cleanedText,
    required String originalText,
    required TextQuality quality,
    required double readableRatio,
  }) {
    return PdfExtractionResult._(
      text: cleanedText,
      originalText: originalText,
      success: true,
      quality: quality,
      readableRatio: readableRatio,
      contentSource: ContentSource.extractedText,
    );
  }

  factory PdfExtractionResult.empty() {
    // TODO: Future improvement - when text extraction fails completely:
    // 1. Render PDF pages as images and send to vision-capable AI model
    // 2. Add OCR fallback for scanned PDFs
    // 3. Send PDF directly to AI providers that support file processing
    return const PdfExtractionResult._(
      text: '',
      originalText: '',
      success: true, // Still success - let AI handle empty gracefully
      quality: TextQuality.empty,
      readableRatio: 0.0,
      contentSource: ContentSource.empty,
    );
  }

  factory PdfExtractionResult.error(String message) {
    return PdfExtractionResult._(
      errorMessage: message,
      success: false,
      quality: TextQuality.empty,
      readableRatio: 0.0,
      contentSource: ContentSource.empty,
    );
  }

  factory PdfExtractionResult.noPath() {
    return const PdfExtractionResult._(
      errorMessage: 'مسار الملف غير متوفر',
      success: false,
      quality: TextQuality.empty,
      readableRatio: 0.0,
      contentSource: ContentSource.empty,
    );
  }

  /// Whether we have any text to send to AI
  bool get hasText => text != null && text!.isNotEmpty;

  /// Whether the quality is limited (medium or low)
  bool get hasLimitedQuality => quality == TextQuality.medium || quality == TextQuality.low;
}

/// Result of getting PDF page count
class PdfPageCountResult {
  final int pageCount;
  final String? errorMessage;
  final bool success;

  const PdfPageCountResult._({
    this.pageCount = 0,
    this.errorMessage,
    required this.success,
  });

  factory PdfPageCountResult.success(int count) {
    return PdfPageCountResult._(pageCount: count, success: true);
  }

  factory PdfPageCountResult.error(String message) {
    return PdfPageCountResult._(errorMessage: message, success: false);
  }
}

class PdfTextService {
  // Quality thresholds (internal only - never block user based on these)
  static const double _highQualityThreshold = 0.70;
  static const double _mediumQualityThreshold = 0.40;

  /// Get the total page count of a PDF file
  Future<PdfPageCountResult> getPageCount(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      return PdfPageCountResult.error('مسار الملف غير متوفر');
    }

    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return PdfPageCountResult.error('الملف غير موجود');
      }

      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final int pageCount = document.pages.count;
      document.dispose();

      debugPrint('[PdfTextService] PDF has $pageCount pages');
      return PdfPageCountResult.success(pageCount);
    } catch (e) {
      debugPrint('[PdfTextService] Error getting page count: $e');
      return PdfPageCountResult.error('حدث خطأ أثناء قراءة الملف');
    }
  }

  /// Extract text from all pages (default behavior)
  Future<PdfExtractionResult> extractText(String? filePath) async {
    return extractTextFromRange(filePath, null, null);
  }

  /// Extract text from a specific page range
  /// [fromPage] and [toPage] are 1-indexed (first page is 1)
  /// If both are null, extracts all pages
  Future<PdfExtractionResult> extractTextFromRange(
    String? filePath,
    int? fromPage,
    int? toPage,
  ) async {
    // Check if file path is null
    if (filePath == null || filePath.isEmpty) {
      return PdfExtractionResult.noPath();
    }

    try {
      // Read the PDF file
      final file = File(filePath);

      if (!await file.exists()) {
        return PdfExtractionResult.error('الملف غير موجود');
      }

      final bytes = await file.readAsBytes();

      // Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final int totalPages = document.pages.count;

      // Determine page range (convert to 0-indexed)
      int startIndex = 0;
      int endIndex = totalPages - 1;

      if (fromPage != null && toPage != null) {
        // Convert 1-indexed to 0-indexed
        startIndex = (fromPage - 1).clamp(0, totalPages - 1);
        endIndex = (toPage - 1).clamp(0, totalPages - 1);

        debugPrint('[PdfTextService] Extracting pages $fromPage to $toPage (indices $startIndex to $endIndex)');
      } else {
        debugPrint('[PdfTextService] Extracting all $totalPages pages');
      }

      // Extract text from the specified page range
      final StringBuffer extractedText = StringBuffer();

      for (int i = startIndex; i <= endIndex; i++) {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);

        if (pageText.isNotEmpty) {
          extractedText.writeln(pageText);
        }
      }

      // Dispose the document
      document.dispose();

      final String originalText = extractedText.toString().trim();

      // Debug log: original extracted text length
      debugPrint('[PdfTextService] Original extracted length: ${originalText.length}');

      // Check if extracted text is completely empty
      if (originalText.isEmpty) {
        debugPrint('[PdfTextService] Quality: EMPTY (no text extracted)');
        debugPrint('[PdfTextService] Content source: empty');
        debugPrint('[PdfTextService] willSendToAI: false (no content)');
        return PdfExtractionResult.empty();
      }

      // Calculate readable ratio (internal metric only)
      final double readableRatio = _calculateReadableRatio(originalText);
      debugPrint('[PdfTextService] Readable ratio: ${(readableRatio * 100).toStringAsFixed(1)}%');

      // Determine quality level (internal rating only - never block user)
      final TextQuality quality = _determineQuality(originalText, readableRatio);
      debugPrint('[PdfTextService] Quality rating: ${quality.name.toUpperCase()}');

      // Clean the text - but NEVER erase it
      final String cleanedText = _cleanText(originalText);
      debugPrint('[PdfTextService] Cleaned text length: ${cleanedText.length}');

      // Always keep the best available content
      // If cleaning removed everything, use original with basic cleanup
      String finalText = cleanedText;
      if (cleanedText.isEmpty && originalText.isNotEmpty) {
        debugPrint('[PdfTextService] Cleaning removed all text, using basic cleanup');
        finalText = _basicCleanup(originalText);
      }

      debugPrint('[PdfTextService] Final text length: ${finalText.length}');
      debugPrint('[PdfTextService] Content source: extracted_text');
      debugPrint('[PdfTextService] willSendToAI: ${finalText.isNotEmpty}');

      if (quality == TextQuality.low) {
        debugPrint('[PdfTextService] Low quality text - will send best available content to AI');
      }

      return PdfExtractionResult.success(
        cleanedText: finalText,
        originalText: originalText,
        quality: quality,
        readableRatio: readableRatio,
      );
    } catch (e) {
      debugPrint('[PdfTextService] Extraction error: $e');
      return PdfExtractionResult.error('حدث خطأ أثناء استخراج النص: ${e.toString()}');
    }
  }

  /// Determines quality level based on readable ratio (internal only)
  TextQuality _determineQuality(String text, double readableRatio) {
    // Check for gibberish patterns that reduce quality
    if (_hasRepeatedGibberish(text)) {
      return TextQuality.low;
    }

    // Check control character ratio
    final controlRatio = _countControlCharacters(text) / text.length;
    if (controlRatio > 0.05) {
      // Demote quality if too many control characters
      if (readableRatio >= _highQualityThreshold) {
        return TextQuality.medium;
      }
      return TextQuality.low;
    }

    if (readableRatio >= _highQualityThreshold) {
      return TextQuality.high;
    } else if (readableRatio >= _mediumQualityThreshold) {
      return TextQuality.medium;
    } else {
      return TextQuality.low;
    }
  }

  /// Calculates the ratio of readable characters in the text
  double _calculateReadableRatio(String text) {
    if (text.isEmpty) return 0.0;

    int readableCount = 0;
    int totalCount = 0;

    for (int i = 0; i < text.length; i++) {
      final int codeUnit = text.codeUnitAt(i);

      // Skip whitespace for ratio calculation
      if (_isWhitespace(codeUnit)) continue;

      totalCount++;

      if (_isReadableCharacter(codeUnit)) {
        readableCount++;
      }
    }

    if (totalCount == 0) return 0.0;
    return readableCount / totalCount;
  }

  /// Checks if a character is considered readable (Arabic, English, numbers, common punctuation)
  bool _isReadableCharacter(int codeUnit) {
    // Arabic characters (0x0600-0x06FF, 0x0750-0x077F, 0x08A0-0x08FF, 0xFB50-0xFDFF, 0xFE70-0xFEFF)
    if ((codeUnit >= 0x0600 && codeUnit <= 0x06FF) ||
        (codeUnit >= 0x0750 && codeUnit <= 0x077F) ||
        (codeUnit >= 0x08A0 && codeUnit <= 0x08FF) ||
        (codeUnit >= 0xFB50 && codeUnit <= 0xFDFF) ||
        (codeUnit >= 0xFE70 && codeUnit <= 0xFEFF)) {
      return true;
    }

    // English letters (A-Z, a-z)
    if ((codeUnit >= 0x0041 && codeUnit <= 0x005A) ||
        (codeUnit >= 0x0061 && codeUnit <= 0x007A)) {
      return true;
    }

    // Numbers (0-9)
    if (codeUnit >= 0x0030 && codeUnit <= 0x0039) {
      return true;
    }

    // Arabic-Indic digits (٠-٩)
    if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
      return true;
    }

    // Extended Arabic-Indic digits (۰-۹)
    if (codeUnit >= 0x06F0 && codeUnit <= 0x06F9) {
      return true;
    }

    // Common punctuation and symbols
    if (_isCommonPunctuation(codeUnit)) {
      return true;
    }

    return false;
  }

  /// Checks if character is whitespace
  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x0020 || // Space
           codeUnit == 0x0009 || // Tab
           codeUnit == 0x000A || // Line feed
           codeUnit == 0x000D || // Carriage return
           codeUnit == 0x00A0;   // Non-breaking space
  }

  /// Checks if character is common punctuation
  bool _isCommonPunctuation(int codeUnit) {
    // Common ASCII punctuation
    const punctuation = [
      0x0021, // !
      0x0022, // "
      0x0027, // '
      0x0028, // (
      0x0029, // )
      0x002C, // ,
      0x002D, // -
      0x002E, // .
      0x003A, // :
      0x003B, // ;
      0x003F, // ?
      0x005B, // [
      0x005D, // ]
      0x007B, // {
      0x007D, // }
    ];

    if (punctuation.contains(codeUnit)) return true;

    // Arabic punctuation
    if (codeUnit >= 0x060C && codeUnit <= 0x061F) return true;

    return false;
  }

  /// Counts control characters in text
  int _countControlCharacters(String text) {
    int count = 0;
    for (int i = 0; i < text.length; i++) {
      final int codeUnit = text.codeUnitAt(i);
      // Control characters (0x00-0x1F except common whitespace, and 0x7F-0x9F)
      if ((codeUnit <= 0x1F && !_isWhitespace(codeUnit)) ||
          (codeUnit >= 0x7F && codeUnit <= 0x9F)) {
        count++;
      }
    }
    return count;
  }

  /// Checks for repeated gibberish patterns indicating encoding issues
  bool _hasRepeatedGibberish(String text) {
    // Check for replacement character (�) appearing too often
    final replacementCount = text.codeUnits.where((c) => c == 0xFFFD).length;
    if (replacementCount > text.length * 0.05) {
      return true;
    }

    // Check for excessive private use area characters
    final privateUseCount = text.codeUnits.where((c) =>
      (c >= 0xE000 && c <= 0xF8FF) ||
      (c >= 0xF0000 && c <= 0xFFFFD) ||
      (c >= 0x100000 && c <= 0x10FFFD)
    ).length;
    if (privateUseCount > text.length * 0.1) {
      return true;
    }

    return false;
  }

  /// Cleans the extracted text by removing unwanted characters
  /// Never erases text completely - always keeps best available content
  String _cleanText(String text) {
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final int codeUnit = text.codeUnitAt(i);

      // Keep readable characters and whitespace
      if (_isReadableCharacter(codeUnit) || _isWhitespace(codeUnit)) {
        buffer.writeCharCode(codeUnit);
      }
    }

    // Normalize whitespace: collapse multiple spaces into one
    String cleaned = buffer.toString();
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim();
  }

  /// Basic cleanup - only removes control characters, keeps everything else
  /// Used as fallback when aggressive cleaning removes too much
  String _basicCleanup(String text) {
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final int codeUnit = text.codeUnitAt(i);

      // Remove only control characters (except whitespace)
      if (codeUnit > 0x1F || _isWhitespace(codeUnit)) {
        // Also remove 0x7F-0x9F control range
        if (codeUnit < 0x7F || codeUnit > 0x9F) {
          buffer.writeCharCode(codeUnit);
        }
      }
    }

    // Basic whitespace normalization
    String cleaned = buffer.toString();
    cleaned = cleaned.replaceAll(RegExp(r' {3,}'), '  ');
    cleaned = cleaned.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');

    return cleaned.trim();
  }
}
