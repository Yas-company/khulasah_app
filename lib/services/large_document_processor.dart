import 'package:flutter/foundation.dart';

import '../models/generated_result.dart';
import 'backend_service.dart';
import 'pdf_text_service.dart';

class LargeDocumentProgress {
  final String message;
  final int currentPart;
  final int totalParts;

  const LargeDocumentProgress({
    required this.message,
    this.currentPart = 0,
    this.totalParts = 0,
  });

  double? get fraction {
    if (totalParts <= 0) return null;
    return (currentPart / totalParts).clamp(0, 1);
  }
}

class LargeDocumentCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class LargeDocumentProcessor {
  static const int largeRangeThreshold = 30;
  static const int _textChunkPages = 30;
  static const int _imageChunkPages = 10;

  /// الحد الأقصى لعمليات OCR المتوازية (لتجنب الضغط على الذاكرة)
  static const int _maxParallelOcrOperations = 4;

  /// الحد الأقصى لطلبات AI المتوازية
  static const int _maxParallelAiRequests = 6;

  final PdfTextService _pdfTextService;
  final BackendService _backendService;

  LargeDocumentProcessor({
    PdfTextService? pdfTextService,
    BackendService? backendService,
  }) : _pdfTextService = pdfTextService ?? PdfTextService(),
       _backendService = backendService ?? BackendService();

  Future<GeneratedResult> process({
    required String filePath,
    required String fileName,
    required int totalPages,
    required int fromPage,
    required int toPage,
    required String outputType,
    required String summaryLength,
    required int targetWords,
    required int targetPages,
    required String outputLanguage,
    required LargeDocumentCancellationToken cancellationToken,
    void Function(LargeDocumentProgress progress)? onProgress,
  }) async {
    final selectedPages = toPage - fromPage + 1;
    debugPrint('[LargeDoc] selected pages: $fromPage-$toPage ($selectedPages)');

    onProgress?.call(
      const LargeDocumentProgress(
        message: 'جاري معالجة الملف، قد يستغرق ذلك وقتًا أطول قليلًا.',
      ),
    );
    _throwIfCancelled(cancellationToken);

    final probeToPage = (fromPage + _textChunkPages - 1).clamp(
      fromPage,
      toPage,
    );
    onProgress?.call(
      const LargeDocumentProgress(message: 'جاري قراءة الصفحات...'),
    );

    final probeResult = await _pdfTextService.extractTextFromRange(
      filePath,
      fromPage,
      probeToPage,
    );
    _throwIfCancelled(cancellationToken);

    final useImageChunks = !probeResult.hasText;
    final chunkSize = useImageChunks ? _imageChunkPages : _textChunkPages;
    final ranges = _buildRanges(fromPage, toPage, chunkSize);

    debugPrint('[LargeDoc] total chunks: ${ranges.length}');
    debugPrint('[LargeDoc] chunk size: $chunkSize');

    // استخراج النصوص بدفعات لتجنب الضغط على الذاكرة
    final maxParallel = useImageChunks
        ? _maxParallelOcrOperations
        : ranges.length; // النص العادي يمكن معالجته بالتوازي الكامل

    onProgress?.call(
      LargeDocumentProgress(
        message: 'جاري استخراج النصوص من ${ranges.length} أجزاء...',
        currentPart: 0,
        totalParts: ranges.length,
      ),
    );

    debugPrint('[LargeDoc] extracting text from ${ranges.length} chunks');
    debugPrint('[LargeDoc] max parallel operations: $maxParallel');

    // استخراج النصوص بدفعات
    final extractedChunks = <_ExtractedChunk>[];
    for (var batchStart = 0; batchStart < ranges.length; batchStart += maxParallel) {
      _throwIfCancelled(cancellationToken);

      final batchEnd = (batchStart + maxParallel).clamp(0, ranges.length);
      final batchRanges = ranges.sublist(batchStart, batchEnd);

      debugPrint('[LargeDoc] processing extraction batch ${batchStart ~/ maxParallel + 1}: chunks ${batchStart + 1}-$batchEnd');

      onProgress?.call(
        LargeDocumentProgress(
          message: 'جاري استخراج النصوص (${batchEnd}/${ranges.length})...',
          currentPart: batchEnd,
          totalParts: ranges.length,
        ),
      );

      final batchFutures = <Future<_ExtractedChunk>>[];
      for (var i = 0; i < batchRanges.length; i++) {
        final range = batchRanges[i];
        final partNumber = batchStart + i + 1;
        batchFutures.add(
          _extractChunk(
            filePath: filePath,
            range: range,
            partNumber: partNumber,
            allowImageFallback: useImageChunks,
            cancellationToken: cancellationToken,
          ),
        );
      }

      final batchResults = await Future.wait(batchFutures);
      extractedChunks.addAll(batchResults);
    }

    _throwIfCancelled(cancellationToken);

    // تصفية الأجزاء الفارغة
    final validChunks = extractedChunks.where((c) => c.text.isNotEmpty).toList();
    debugPrint('[LargeDoc] valid chunks: ${validChunks.length}/${ranges.length}');

    if (validChunks.isEmpty) {
      return GeneratedResult.error(
        'تعذر قراءة الملف. جرّب اختيار صفحات أقل أو ملف أوضح.',
      );
    }

    // إرسال الأجزاء للـ AI بدفعات
    onProgress?.call(
      LargeDocumentProgress(
        message: 'جاري معالجة ${validChunks.length} أجزاء...',
        currentPart: 0,
        totalParts: validChunks.length,
      ),
    );

    debugPrint('[LargeDoc] sending ${validChunks.length} chunks to AI');
    debugPrint('[LargeDoc] max parallel AI requests: $_maxParallelAiRequests');

    final summaryResults = <_PartialSummaryResult>[];
    for (var batchStart = 0; batchStart < validChunks.length; batchStart += _maxParallelAiRequests) {
      _throwIfCancelled(cancellationToken);

      final batchEnd = (batchStart + _maxParallelAiRequests).clamp(0, validChunks.length);
      final batchChunks = validChunks.sublist(batchStart, batchEnd);

      debugPrint('[LargeDoc] processing AI batch ${batchStart ~/ _maxParallelAiRequests + 1}: chunks ${batchStart + 1}-$batchEnd');

      onProgress?.call(
        LargeDocumentProgress(
          message: 'جاري إنشاء الملخصات (${batchEnd}/${validChunks.length})...',
          currentPart: batchEnd,
          totalParts: validChunks.length,
        ),
      );

      final batchFutures = <Future<_PartialSummaryResult>>[];
      for (final chunk in batchChunks) {
        final chunkRangeLabel = outputLanguage == 'en'
            ? 'Pages ${chunk.range.fromPage}-${chunk.range.toPage}, '
                  'part ${chunk.partNumber} of ${ranges.length}'
            : 'الصفحات ${chunk.range.fromPage}-${chunk.range.toPage}، '
                  'الجزء ${chunk.partNumber} من ${ranges.length}';

        batchFutures.add(
          _generatePartialSummary(
            text: chunk.text,
            fileName: fileName,
            range: chunk.range,
            partNumber: chunk.partNumber,
            totalParts: ranges.length,
            summaryLength: summaryLength,
            outputLanguage: outputLanguage,
            totalDocumentPages: totalPages,
            partialTargetWords: _partialTargetWords(targetWords),
            chunkRangeLabel: chunkRangeLabel,
          ),
        );
      }

      final batchResults = await Future.wait(batchFutures);
      summaryResults.addAll(batchResults);
    }

    _throwIfCancelled(cancellationToken);

    // جمع الملخصات الناجحة
    final partialSummaries = <String>[];
    for (final result in summaryResults) {
      if (result.summary != null && result.summary!.isNotEmpty) {
        final partLabel = outputLanguage == 'en'
            ? 'Part ${result.partNumber}, pages ${result.range.fromPage}-${result.range.toPage}'
            : 'الجزء ${result.partNumber}، الصفحات ${result.range.fromPage}-${result.range.toPage}';
        partialSummaries.add('$partLabel:\n${result.summary}');
        debugPrint('[LargeDoc] partial summary success: ${result.partNumber}');
      } else {
        debugPrint('[LargeDoc] partial summary failed: ${result.partNumber}');
      }
    }

    onProgress?.call(
      LargeDocumentProgress(
        message: 'تم معالجة ${partialSummaries.length} من ${ranges.length} أجزاء',
        currentPart: partialSummaries.length,
        totalParts: ranges.length,
      ),
    );

    _throwIfCancelled(cancellationToken);

    if (partialSummaries.isEmpty) {
      return GeneratedResult.error(
        'تعذر قراءة الملف. جرّب اختيار صفحات أقل أو ملف أوضح.',
      );
    }

    onProgress?.call(
      LargeDocumentProgress(
        message: 'جاري تجهيز الملخص النهائي...',
        currentPart: ranges.length,
        totalParts: ranges.length,
      ),
    );

    debugPrint('[LargeDoc] final summary request: ${partialSummaries.length}');
    final finalResult = await _backendService.generateFromText(
      extractedText: partialSummaries.join('\n\n'),
      outputType: outputType,
      summaryLength: summaryLength,
      outputLanguage: outputLanguage,
      fileName: fileName,
      fromPage: fromPage,
      toPage: toPage,
      totalPages: totalPages,
      pageRangeLabel: fromPage == 1 && toPage == totalPages
          ? 'كل الصفحات'
          : 'من صفحة $fromPage إلى صفحة $toPage',
      mode: 'final',
      targetWords: targetWords,
      targetPages: targetPages,
    );

    _throwIfCancelled(cancellationToken);

    if (finalResult != null && finalResult.success) {
      debugPrint('[LargeDoc] final summary success: true');
      return finalResult;
    }

    debugPrint('[LargeDoc] final summary success: false');
    return GeneratedResult.error(
      'تعذر تجهيز الملخص النهائي. يرجى المحاولة مرة أخرى.',
    );
  }

  int _partialTargetWords(int finalTargetWords) {
    if (finalTargetWords >= 5000) return 1000;
    if (finalTargetWords >= 2500) return 800;
    return 600;
  }

  Future<PdfExtractionResult> _extractRange({
    required String filePath,
    required _PageRange range,
    required bool allowImageFallback,
    required LargeDocumentCancellationToken cancellationToken,
  }) async {
    if (allowImageFallback) {
      final extraction = await _pdfTextService.extractTextWithOcrFallback(
        filePath: filePath,
        fromPage: range.fromPage,
        toPage: range.toPage,
      );
      return extraction.extractionResult;
    }

    final normalResult = await _pdfTextService.extractTextFromRange(
      filePath,
      range.fromPage,
      range.toPage,
    );
    if (normalResult.hasText || !normalResult.success) {
      return normalResult;
    }

    final imageRanges = _buildRanges(
      range.fromPage,
      range.toPage,
      _imageChunkPages,
    );
    final textParts = <String>[];

    for (final imageRange in imageRanges) {
      _throwIfCancelled(cancellationToken);
      final extraction = await _pdfTextService.extractTextWithOcrFallback(
        filePath: filePath,
        fromPage: imageRange.fromPage,
        toPage: imageRange.toPage,
      );
      final text = extraction.extractionResult.text?.trim();
      if (text != null && text.isNotEmpty) {
        textParts.add(text);
      }
    }

    if (textParts.isEmpty) {
      return PdfExtractionResult.empty();
    }

    return PdfExtractionResult.fromOcr(
      text: textParts.join('\n\n'),
      quality: TextQuality.medium,
    );
  }

  List<_PageRange> _buildRanges(int fromPage, int toPage, int chunkSize) {
    final ranges = <_PageRange>[];
    var start = fromPage;

    while (start <= toPage) {
      final end = (start + chunkSize - 1).clamp(start, toPage);
      ranges.add(_PageRange(start, end));
      start = end + 1;
    }

    return ranges;
  }

  /// استخراج النص من جزء واحد
  Future<_ExtractedChunk> _extractChunk({
    required String filePath,
    required _PageRange range,
    required int partNumber,
    required bool allowImageFallback,
    required LargeDocumentCancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);

      final extraction = await _extractRange(
        filePath: filePath,
        range: range,
        allowImageFallback: allowImageFallback,
        cancellationToken: cancellationToken,
      );

      final text = extraction.text?.trim() ?? '';
      debugPrint('[LargeDoc] chunk $partNumber extracted: ${text.length} chars');

      return _ExtractedChunk(
        range: range,
        partNumber: partNumber,
        text: text,
      );
    } catch (e) {
      debugPrint('[LargeDoc] chunk $partNumber extraction failed: $e');
      return _ExtractedChunk(
        range: range,
        partNumber: partNumber,
        text: '',
      );
    }
  }

  /// إنشاء ملخص جزئي لجزء واحد
  Future<_PartialSummaryResult> _generatePartialSummary({
    required String text,
    required String fileName,
    required _PageRange range,
    required int partNumber,
    required int totalParts,
    required String summaryLength,
    required String outputLanguage,
    required int totalDocumentPages,
    required int partialTargetWords,
    required String chunkRangeLabel,
  }) async {
    try {
      final partialResult = await _backendService.generateFromText(
        extractedText: text,
        outputType: 'summaryOnly',
        summaryLength: summaryLength,
        outputLanguage: outputLanguage,
        fileName: fileName,
        fromPage: range.fromPage,
        toPage: range.toPage,
        totalPages: totalDocumentPages,
        pageRangeLabel: chunkRangeLabel,
        mode: 'partial',
        targetWords: partialTargetWords,
        targetPages: 1,
      );

      final summary = partialResult?.summary?.trim();
      return _PartialSummaryResult(
        range: range,
        partNumber: partNumber,
        summary: summary,
      );
    } catch (e) {
      debugPrint('[LargeDoc] partial summary $partNumber failed: $e');
      return _PartialSummaryResult(
        range: range,
        partNumber: partNumber,
        summary: null,
      );
    }
  }

  void _throwIfCancelled(LargeDocumentCancellationToken token) {
    if (token.isCancelled) {
      throw const LargeDocumentCancelledException();
    }
  }
}

class LargeDocumentCancelledException implements Exception {
  const LargeDocumentCancelledException();
}

class _PageRange {
  final int fromPage;
  final int toPage;

  const _PageRange(this.fromPage, this.toPage);
}

class _ExtractedChunk {
  final _PageRange range;
  final int partNumber;
  final String text;

  const _ExtractedChunk({
    required this.range,
    required this.partNumber,
    required this.text,
  });
}

class _PartialSummaryResult {
  final _PageRange range;
  final int partNumber;
  final String? summary;

  const _PartialSummaryResult({
    required this.range,
    required this.partNumber,
    required this.summary,
  });
}
