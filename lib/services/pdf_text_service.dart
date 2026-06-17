import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'ocr_service.dart';

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

/// Content source for AI processing (internal only - never shown to user)
enum ContentSource {
  /// Text was extracted from PDF directly
  extractedText,
  /// Text was extracted via internal image processing (OCR)
  ocrText,
  /// No content available
  empty,
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
    ContentSource contentSource = ContentSource.extractedText,
  }) {
    return PdfExtractionResult._(
      text: cleanedText,
      originalText: originalText,
      success: true,
      quality: quality,
      readableRatio: readableRatio,
      contentSource: contentSource,
    );
  }

  /// Result from internal image processing (OCR) fallback
  factory PdfExtractionResult.fromOcr({
    required String text,
    required TextQuality quality,
  }) {
    return PdfExtractionResult._(
      text: text,
      originalText: text,
      success: true,
      quality: quality,
      readableRatio: quality == TextQuality.high ? 0.9 : 0.6,
      contentSource: ContentSource.ocrText,
    );
  }

  factory PdfExtractionResult.empty() {
    return const PdfExtractionResult._(
      text: '',
      originalText: '',
      success: true,
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

/// Result status for extraction with OCR fallback
enum ExtractionStatus {
  /// Text extracted successfully (either direct or OCR)
  success,
  /// Normal extraction returned empty, OCR fallback not attempted (too many pages)
  tooManyPagesForOcr,
  /// Both normal extraction and OCR fallback failed
  failed,
  /// File error (not found, invalid path, etc.)
  fileError,
}

/// Extended result that includes OCR fallback status
class ExtendedExtractionResult {
  final PdfExtractionResult extractionResult;
  final ExtractionStatus status;
  final String? statusMessage;

  const ExtendedExtractionResult({
    required this.extractionResult,
    required this.status,
    this.statusMessage,
  });

  bool get hasText => extractionResult.hasText;
  bool get isOcrSource => extractionResult.contentSource == ContentSource.ocrText;
}

class PdfTextService {
  // Quality thresholds (internal only - never block user based on these)
  static const double _highQualityThreshold = 0.70;
  static const double _mediumQualityThreshold = 0.40;

  // OCR fallback limits (internal only)
  static const int maxOcrPagesPerRequest = 10;

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

  /// Extract text with automatic internal OCR fallback for scanned PDFs.
  ///
  /// Flow:
  /// 1. Try normal text extraction first
  /// 2. If text exists, return it with source 'extractedText'
  /// 3. If empty and page count <= maxOcrPagesPerRequest, try internal OCR
  /// 4. Return OCR text with source 'ocrText' if successful
  /// 5. Return empty if OCR also fails
  ///
  /// Callbacks:
  /// - [onNormalExtractionStart] called when starting normal extraction
  /// - [onOcrFallbackStart] called when starting OCR fallback (for UI feedback)
  /// - [onPageProcessed] called for each page during OCR (current, total)
  Future<ExtendedExtractionResult> extractTextWithOcrFallback({
    required String? filePath,
    required int fromPage,
    required int toPage,
    void Function()? onNormalExtractionStart,
    void Function()? onOcrFallbackStart,
    void Function(int current, int total)? onPageProcessed,
  }) async {
    // Validate file path
    if (filePath == null || filePath.isEmpty) {
      debugPrint('[OCR] File path is null or empty');
      return ExtendedExtractionResult(
        extractionResult: PdfExtractionResult.noPath(),
        status: ExtractionStatus.fileError,
      );
    }

    final pageCount = toPage - fromPage + 1;
    debugPrint('[OCR] Selected page count: $pageCount');
    debugPrint('[OCR] OCR page limit: $maxOcrPagesPerRequest');

    // Step 1: Try normal text extraction first
    onNormalExtractionStart?.call();
    debugPrint('[OCR] Attempting normal text extraction...');

    final normalResult = await extractTextFromRange(filePath, fromPage, toPage);

    // Check for file errors
    if (!normalResult.success) {
      debugPrint('[OCR] Normal extraction failed: ${normalResult.errorMessage}');
      return ExtendedExtractionResult(
        extractionResult: normalResult,
        status: ExtractionStatus.fileError,
        statusMessage: normalResult.errorMessage,
      );
    }

    // Step 2: If text was extracted, return it
    if (normalResult.hasText) {
      debugPrint('[OCR] Normal extraction succeeded: ${normalResult.text!.length} chars');
      return ExtendedExtractionResult(
        extractionResult: normalResult,
        status: ExtractionStatus.success,
      );
    }

    // Step 3: Normal extraction returned empty - check if OCR is feasible
    debugPrint('[OCR] Normal extraction empty');

    if (pageCount > maxOcrPagesPerRequest) {
      debugPrint('[OCR] Page count $pageCount exceeds OCR limit $maxOcrPagesPerRequest');
      return ExtendedExtractionResult(
        extractionResult: PdfExtractionResult.empty(),
        status: ExtractionStatus.tooManyPagesForOcr,
        statusMessage: 'Selected page count exceeds OCR limit',
      );
    }

    // Step 4: Try internal OCR fallback
    debugPrint('[OCR] Starting internal OCR fallback');
    onOcrFallbackStart?.call();

    try {
      final ocrResult = await _performOcrFallback(
        filePath: filePath,
        fromPage: fromPage,
        toPage: toPage,
        onPageProcessed: onPageProcessed,
      );

      if (ocrResult.hasText) {
        debugPrint('[OCR] OCR extracted chars: ${ocrResult.text!.length}');
        return ExtendedExtractionResult(
          extractionResult: ocrResult,
          status: ExtractionStatus.success,
        );
      } else {
        debugPrint('[OCR] OCR returned no text');
        return ExtendedExtractionResult(
          extractionResult: PdfExtractionResult.empty(),
          status: ExtractionStatus.failed,
          statusMessage: 'Could not extract text from pages',
        );
      }
    } catch (e) {
      debugPrint('[OCR] OCR failed: $e');
      return ExtendedExtractionResult(
        extractionResult: PdfExtractionResult.empty(),
        status: ExtractionStatus.failed,
        statusMessage: e.toString(),
      );
    }
  }

  /// Internal method to perform OCR on PDF pages using native PDFKit + Vision
  Future<PdfExtractionResult> _performOcrFallback({
    required String filePath,
    required int fromPage,
    required int toPage,
    void Function(int current, int total)? onPageProcessed,
  }) async {
    final ocrService = OcrService.instance;

    // Check if OCR is available
    final isAvailable = await ocrService.isAvailable();
    if (!isAvailable) {
      debugPrint('[OCR] OCR unavailable on this device');
      return PdfExtractionResult.empty();
    }

    // Use native PDFKit + Vision for PDF OCR (handles rendering internally)
    debugPrint('[OCR] Calling native PDF OCR for pages $fromPage-$toPage');

    final ocrResult = await ocrService.recognizeTextFromPdfPages(
      filePath: filePath,
      fromPage: fromPage,
      toPage: toPage,
    );

    if (!ocrResult.success) {
      debugPrint('[OCR] Native OCR failed: ${ocrResult.errorMessage}');
      return PdfExtractionResult.empty();
    }

    if (!ocrResult.hasText) {
      debugPrint('[OCR] Native OCR returned no text');
      return PdfExtractionResult.empty();
    }

    // Clean and return OCR text
    final cleanedText = _cleanText(ocrResult.text!);
    final quality = cleanedText.length > 500 ? TextQuality.high : TextQuality.medium;

    debugPrint('[OCR] Native OCR success: ${cleanedText.length} chars, quality: ${quality.name}');

    return PdfExtractionResult.fromOcr(
      text: cleanedText,
      quality: quality,
    );
  }
}
