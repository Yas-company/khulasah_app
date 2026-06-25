import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const int _maxAiGroupPages = 30;
  static const int _maxAiGroupChars = 28000;
  static const String _partialCachePrefix = 'large_doc_partial_v1';
  static const String _extractionCachePrefix = 'large_doc_text_v1';
  static const String _finalCachePrefix = 'large_doc_final_v1';

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
    required BuildContext context,
    required String filePath,
    required String fileName,
    required int fileSize,
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

    final finalCacheKey = _buildFinalCacheKey(
      fileName: fileName,
      fileSize: fileSize,
      fromPage: fromPage,
      toPage: toPage,
      outputType: outputType,
      summaryLength: summaryLength,
      targetWords: targetWords,
      targetPages: targetPages,
      outputLanguage: outputLanguage,
    );
    final cachedFinalResult = await _readCachedFinalResult(finalCacheKey);
    if (cachedFinalResult != null) {
      debugPrint('[LargeDoc] final cache hit');
      return cachedFinalResult;
    }

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
      const LargeDocumentProgress(message: 'جاري قراءة الصفحات...'),
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
        const LargeDocumentProgress(message: 'جاري قراءة الصفحات...'),
      );

      final batchFutures = <Future<_ExtractedChunk>>[];
      for (var i = 0; i < batchRanges.length; i++) {
        final range = batchRanges[i];
        final partNumber = batchStart + i + 1;
        batchFutures.add(
          _extractChunk(
            filePath: filePath,
            fileName: fileName,
            fileSize: fileSize,
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

    final aiGroups = useImageChunks
        ? _buildAiGroups(validChunks)
        : validChunks.map(_AiGroup.fromChunk).toList();

    debugPrint('[LargeDoc] AI groups: ${aiGroups.length}');

    // إرسال الأجزاء للـ AI بدفعات
    onProgress?.call(
      LargeDocumentProgress(
        message: 'جاري معالجة ${aiGroups.length} أجزاء...',
        currentPart: 0,
        totalParts: aiGroups.length,
      ),
    );

    debugPrint('[LargeDoc] sending ${aiGroups.length} groups to AI');
    debugPrint('[LargeDoc] max parallel AI requests: $_maxParallelAiRequests');

    final summaryResults = <_PartialSummaryResult>[];
    for (var batchStart = 0; batchStart < aiGroups.length; batchStart += _maxParallelAiRequests) {
      _throwIfCancelled(cancellationToken);

      final batchEnd = (batchStart + _maxParallelAiRequests).clamp(0, aiGroups.length);
      final batchGroups = aiGroups.sublist(batchStart, batchEnd);

      debugPrint('[LargeDoc] processing AI batch ${batchStart ~/ _maxParallelAiRequests + 1}: groups ${batchStart + 1}-$batchEnd');

      onProgress?.call(
        LargeDocumentProgress(
          message: 'جاري معالجة الجزء $batchEnd من ${aiGroups.length}...',
          currentPart: batchEnd,
          totalParts: aiGroups.length,
        ),
      );

      final batchFutures = <Future<_PartialSummaryResult>>[];
      for (var i = 0; i < batchGroups.length; i++) {
        final group = batchGroups[i];
        final groupNumber = batchStart + i + 1;
        final groupRangeLabel = outputLanguage == 'en'
            ? 'Pages ${group.fromPage}-${group.toPage}, part $groupNumber of ${aiGroups.length}'
            : 'الصفحات ${group.fromPage}-${group.toPage}، الجزء $groupNumber من ${aiGroups.length}';

        batchFutures.add(
          _generateGroupedPartialSummary(
            text: group.text,
            fileName: fileName,
            fileSize: fileSize,
            range: _PageRange(group.fromPage, group.toPage),
            partNumber: groupNumber,
            totalParts: aiGroups.length,
            summaryLength: summaryLength,
            outputLanguage: outputLanguage,
            totalDocumentPages: totalPages,
            partialTargetWords: _partialTargetWords(targetWords, useImageChunks),
            groupRangeLabel: groupRangeLabel,
            cacheRangeLabel: '$fromPage-$toPage',
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
        message: 'تم معالجة ${partialSummaries.length} من ${aiGroups.length} أجزاء',
        currentPart: partialSummaries.length,
        totalParts: aiGroups.length,
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
        currentPart: aiGroups.length,
        totalParts: aiGroups.length,
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
      await _writeCachedFinalResult(finalCacheKey, finalResult);
      return finalResult;
    }

    debugPrint('[LargeDoc] final summary success: false');
    return GeneratedResult.error(
      'تعذر تجهيز الملخص النهائي. يرجى المحاولة مرة أخرى.',
    );
  }

  int _partialTargetWords(int finalTargetWords, bool groupedScannedDocument) {
    if (finalTargetWords >= 5000) return groupedScannedDocument ? 1200 : 1000;
    if (finalTargetWords >= 2500) return groupedScannedDocument ? 1000 : 800;
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

  List<_AiGroup> _buildAiGroups(List<_ExtractedChunk> chunks) {
    final groups = <_AiGroup>[];
    var currentGroup = _AiGroup.empty();

    for (final chunk in chunks) {
      final nextPageCount = currentGroup.pageCount + chunk.pageCount;
      final nextCharCount = currentGroup.characterCount + chunk.text.length;

      if (currentGroup.isNotEmpty &&
          (nextPageCount > _maxAiGroupPages ||
              nextCharCount > _maxAiGroupChars)) {
        groups.add(currentGroup);
        currentGroup = _AiGroup.empty();
      }

      currentGroup.add(chunk);
      debugPrint(
        '[LargeDoc] OCR chunk range: ${chunk.range.fromPage}-${chunk.range.toPage}',
      );
      debugPrint('[LargeDoc] OCR chunk chars: ${chunk.text.length}');

      if (currentGroup.pageCount >= _maxAiGroupPages ||
          currentGroup.characterCount >= 25000) {
        groups.add(currentGroup);
        currentGroup = _AiGroup.empty();
      }
    }

    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      debugPrint(
        '[LargeDoc] AI group range: ${group.fromPage}-${group.toPage}',
      );
      debugPrint('[LargeDoc] AI group pages: ${group.pageCount}');
      debugPrint('[LargeDoc] AI group chars: ${group.characterCount}');
    }

    return groups;
  }

  /// استخراج النص من جزء واحد
  Future<_ExtractedChunk> _extractChunk({
    required String filePath,
    required String fileName,
    required int fileSize,
    required _PageRange range,
    required int partNumber,
    required bool allowImageFallback,
    required LargeDocumentCancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final cacheKey = _buildExtractionCacheKey(
        fileName: fileName,
        fileSize: fileSize,
        fromPage: range.fromPage,
        toPage: range.toPage,
        allowImageFallback: allowImageFallback,
      );
      final prefs = await SharedPreferences.getInstance();
      final cachedText = prefs.getString(cacheKey)?.trim();
      if (cachedText != null && cachedText.isNotEmpty) {
        debugPrint('[LargeDoc] extraction cache hit: $partNumber');
        return _ExtractedChunk(
          range: range,
          partNumber: partNumber,
          text: cachedText,
        );
      }

      final extraction = await _extractRange(
        filePath: filePath,
        range: range,
        allowImageFallback: allowImageFallback,
        cancellationToken: cancellationToken,
      );

      final text = extraction.text?.trim() ?? '';
      debugPrint('[LargeDoc] chunk $partNumber extracted: ${text.length} chars');
      if (text.isNotEmpty) {
        await prefs.setString(cacheKey, text);
      }

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

  /// إنشاء ملخص جزئي لمجموعة صفحات
  Future<_PartialSummaryResult> _generateGroupedPartialSummary({
    required String text,
    required String fileName,
    required int fileSize,
    required _PageRange range,
    required int partNumber,
    required int totalParts,
    required String summaryLength,
    required String outputLanguage,
    required int totalDocumentPages,
    required int partialTargetWords,
    required String groupRangeLabel,
    required String cacheRangeLabel,
  }) async {
    final cacheKey = _buildPartialCacheKey(
      fileName: fileName,
      fileSize: fileSize,
      selectedRangeLabel: cacheRangeLabel,
      groupRange: '${range.fromPage}-${range.toPage}',
      summaryLength: summaryLength,
      outputLanguage: outputLanguage,
    );

    final prefs = await SharedPreferences.getInstance();
    final cachedSummary = prefs.getString(cacheKey)?.trim();
    if (cachedSummary != null && cachedSummary.isNotEmpty) {
      debugPrint('[LargeDoc] AI partial cache hit: $partNumber');
      return _PartialSummaryResult(
        range: range,
        partNumber: partNumber,
        summary: cachedSummary,
      );
    }

    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        debugPrint('[LargeDoc] AI partial request: $partNumber/$totalParts');
        final partialResult = await _backendService.generateFromText(
          extractedText: text,
          outputType: 'summaryOnly',
          summaryLength: summaryLength,
          outputLanguage: outputLanguage,
          fileName: fileName,
          fromPage: range.fromPage,
          toPage: range.toPage,
          totalPages: totalDocumentPages,
          pageRangeLabel: groupRangeLabel,
          mode: 'partial',
          targetWords: partialTargetWords,
          targetPages: 2,
        );

        final summary = partialResult?.summary?.trim();
        if (summary != null && summary.isNotEmpty) {
          await prefs.setString(cacheKey, summary);
          debugPrint('[LargeDoc] AI partial success: $partNumber');
          return _PartialSummaryResult(
            range: range,
            partNumber: partNumber,
            summary: summary,
          );
        }

        lastError = 'empty summary';
      } catch (e) {
        lastError = e;
      }

      debugPrint(
        '[LargeDoc] AI partial failed: $partNumber attempt $attempt: $lastError',
      );
    }

    return _PartialSummaryResult(
      range: range,
      partNumber: partNumber,
      summary: null,
    );
  }

  String _buildPartialCacheKey({
    required String fileName,
    required int fileSize,
    required String selectedRangeLabel,
    required String groupRange,
    required String summaryLength,
    required String outputLanguage,
  }) {
    final rawKey = [
      _partialCachePrefix,
      fileName,
      fileSize,
      selectedRangeLabel,
      groupRange,
      summaryLength,
      outputLanguage,
    ].join('|');
    return '$_partialCachePrefix:${base64Url.encode(utf8.encode(rawKey))}';
  }

  String _buildExtractionCacheKey({
    required String fileName,
    required int fileSize,
    required int fromPage,
    required int toPage,
    required bool allowImageFallback,
  }) {
    final rawKey = [
      _extractionCachePrefix,
      fileName,
      fileSize,
      fromPage,
      toPage,
      allowImageFallback ? 'ocr' : 'text',
    ].join('|');
    return '$_extractionCachePrefix:${base64Url.encode(utf8.encode(rawKey))}';
  }

  String _buildFinalCacheKey({
    required String fileName,
    required int fileSize,
    required int fromPage,
    required int toPage,
    required String outputType,
    required String summaryLength,
    required int targetWords,
    required int targetPages,
    required String outputLanguage,
  }) {
    final rawKey = [
      _finalCachePrefix,
      fileName,
      fileSize,
      fromPage,
      toPage,
      outputType,
      summaryLength,
      targetWords,
      targetPages,
      outputLanguage,
    ].join('|');
    return '$_finalCachePrefix:${base64Url.encode(utf8.encode(rawKey))}';
  }

  Future<GeneratedResult?> _readCachedFinalResult(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(cacheKey);
    if (rawJson == null || rawJson.isEmpty) return null;

    try {
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      final qaRaw = data['questionsAndAnswers'];
      final qaList = qaRaw is List
          ? qaRaw
                .map(
                  (item) => QuestionAnswer(
                    question: item['question']?.toString() ?? '',
                    answer: item['answer']?.toString() ?? '',
                  ),
                )
                .where((item) => item.question.isNotEmpty || item.answer.isNotEmpty)
                .toList()
          : null;
      return GeneratedResult(
        success: true,
        summary: data['summary']?.toString(),
        questionsAndAnswers: qaList,
        resultType: _resultTypeFromString(data['resultType']?.toString()),
        generatedAt:
            DateTime.tryParse(data['generatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      debugPrint('[LargeDoc] final cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeCachedFinalResult(
    String cacheKey,
    GeneratedResult result,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'summary': result.summary,
      'questionsAndAnswers': result.questionsAndAnswers
          ?.map((item) => {'question': item.question, 'answer': item.answer})
          .toList(),
      'resultType': result.resultType.name,
      'generatedAt': result.generatedAt.toIso8601String(),
    };
    await prefs.setString(cacheKey, jsonEncode(data));
  }

  GeneratedResultType _resultTypeFromString(String? value) {
    switch (value) {
      case 'questionsOnly':
        return GeneratedResultType.questionsOnly;
      case 'summaryAndQuestions':
        return GeneratedResultType.summaryAndQuestions;
      default:
        return GeneratedResultType.summaryOnly;
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

  int get pageCount => range.toPage - range.fromPage + 1;
}

class _AiGroup {
  final List<_ExtractedChunk> chunks;

  _AiGroup.empty() : chunks = [];

  _AiGroup.fromChunk(_ExtractedChunk chunk) : chunks = [chunk];

  bool get isNotEmpty => chunks.isNotEmpty;

  int get fromPage => chunks.first.range.fromPage;

  int get toPage => chunks.last.range.toPage;

  int get pageCount => chunks.fold(0, (sum, chunk) => sum + chunk.pageCount);

  int get characterCount =>
      chunks.fold(0, (sum, chunk) => sum + chunk.text.length);

  String get text => chunks.map((chunk) => chunk.text).join('\n\n');

  void add(_ExtractedChunk chunk) {
    chunks.add(chunk);
  }
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
