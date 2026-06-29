import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/generated_result.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import 'firebase_functions_service.dart';

/// Backend service that handles communication with AI/summarization services.
///
/// This service uses a priority-based approach:
/// 1. Try backend (local in debug, Cloudflare Worker in release)
/// 2. If backend fails, try Firebase Cloud Functions
/// 3. Debug only: If all backends fail, use local dummy generation
/// 4. Release: Show friendly error message if all backends fail
///
/// SECURITY NOTES:
/// - Never store API keys in Flutter/Dart code
/// - All AI API calls go through backend services
/// - Debug: Local Node.js backend with OpenRouter
/// - Release: Cloudflare Worker with OpenRouter
class BackendService {
  final FirebaseFunctionsService _firebaseService =
      FirebaseFunctionsService.instance;

  /// Returns question count based on selected page range
  int _getQuestionCount(int selectedPageCount) {
    if (selectedPageCount <= 10) return 5;
    if (selectedPageCount <= 25) return 10;
    if (selectedPageCount <= 50) return 15;
    return 20;
  }

  /// Generates a result based on the selected options.
  ///
  /// This method tries backends in order:
  /// 1. Local Node.js backend (OpenRouter)
  /// 2. Firebase Cloud Functions
  /// 3. Local dummy generation (fallback)
  ///
  /// Parameters:
  /// - [fileInfo]: Information about the selected PDF file including extracted text
  /// - [options]: User-selected output type and length preferences
  ///
  /// Returns:
  /// A [GeneratedResult] containing the summary, Q&A, or both based on options.
  Future<GeneratedResult> generateResult({
    required SelectedFileInfo fileInfo,
    required SummaryOptions options,
    void Function(String message)? onProgress,
  }) async {
    // Debug log input state
    debugPrint('[Backend] generateResult called');
    debugPrint('[Backend] hasExtractedText: ${fileInfo.hasExtractedText}');
    debugPrint(
      '[Backend] extractedTextLength: ${fileInfo.extractedTextLength}',
    );
    debugPrint('[Backend] textQuality: ${fileInfo.textQuality.name}');
    debugPrint('[Backend] outputTypeIndex: ${options.outputTypeIndex}');

    // Always attempt generation - let AI handle any quality issues gracefully
    // Only fail if we have absolutely no content at all
    final textToSend = fileInfo.extractedText ?? '';
    if (textToSend.isEmpty) {
      debugPrint('[Backend] No text available - returning error');
      return GeneratedResult.error('لا يوجد نص مستخرج من الملف للمعالجة');
    }

    onProgress?.call('جاري إنشاء الملخص...');

    // Try primary backend first (local in debug, Cloudflare Worker in release)
    debugPrint('[Backend] Trying primary backend...');
    try {
      final result = await _tryPrimaryBackend(fileInfo, options);
      if (result != null) {
        debugPrint('[Backend] Primary backend success');
        return result;
      }
    } catch (e) {
      debugPrint('[Backend] Primary backend failed: $e');
    }

    // Try Firebase Cloud Functions second
    debugPrint('[Backend] Trying Firebase Cloud Functions...');
    try {
      final result = await _tryFirebaseGeneration(fileInfo, options);
      if (result != null) {
        debugPrint('[Backend] Firebase Cloud Function success');
        return result;
      }
    } catch (e) {
      debugPrint('[Backend] Firebase generation failed: $e');
    }

    // In release mode, don't use local dummy fallback - show error instead
    if (AppConfig.isRelease) {
      debugPrint(
        '[Backend] Release mode - all backends failed, returning error',
      );
      return GeneratedResult.error(
        'تعذر الاتصال بخدمة التلخيص حالياً، يرجى المحاولة لاحقاً.',
      );
    }

    // Debug mode: If we have real text content (OCR or extracted), don't use dummy
    // Only use dummy for testing when there's no meaningful content
    final hasRealContent = textToSend.length > 100;
    if (hasRealContent) {
      debugPrint(
        '[Backend] Debug mode - real content exists (${textToSend.length} chars), showing error instead of dummy',
      );
      return GeneratedResult.error(
        'تعذر الاتصال بخدمة التلخيص. تأكد من اتصال الإنترنت وحاول مرة أخرى.',
      );
    }

    // Debug mode only: Fallback to local dummy generation (for testing without content)
    debugPrint('[Backend] Debug mode - using local dummy fallback...');
    final result = await _generateLocalDummyResult(fileInfo, options);
    debugPrint('[Backend] Local dummy result generated');
    return result;
  }

  /// Attempts to generate result using the primary backend.
  ///
  /// In debug mode: Local Node.js backend
  /// In release mode: Cloudflare Worker
  ///
  /// Returns null if backend is not available or call fails.
  Future<GeneratedResult?> _tryPrimaryBackend(
    SelectedFileInfo fileInfo,
    SummaryOptions options,
  ) async {
    // Map output type index to string
    final outputTypeMap = {
      0: 'summaryOnly',
      1: 'questionsOnly',
      2: 'summaryAndQuestions',
    };

    final outputType = outputTypeMap[options.outputTypeIndex] ?? 'summaryOnly';
    final summaryLength = options.summaryLength;
    final outputLanguage = options.outputLanguageCode;

    return generateFromText(
      extractedText: fileInfo.extractedText!,
      outputType: outputType,
      summaryLength: summaryLength,
      outputLanguage: outputLanguage,
      fileName: fileInfo.fileName,
      fromPage: fileInfo.actualFromPage,
      toPage: fileInfo.actualToPage,
      totalPages: fileInfo.totalPages,
      pageRangeLabel: fileInfo.pageRangeLabel,
      mode: 'single',
      targetWords: options.targetWords,
      targetPages: options.targetPages,
    );
  }

  Future<GeneratedResult?> generateFromText({
    required String extractedText,
    required String outputType,
    required String summaryLength,
    required String outputLanguage,
    required String fileName,
    required int fromPage,
    required int toPage,
    required int totalPages,
    required String pageRangeLabel,
    String mode = 'single',
    required int targetWords,
    required int targetPages,
  }) async {
    final backendUrl = AppConfig.backendUrl;
    debugPrint('[Backend] Calling $backendUrl/generate-result');
    debugPrint(
      '[Backend] Output type: $outputType, Length: $summaryLength, Language: $outputLanguage',
    );
    debugPrint('[Backend] Text length: ${extractedText.length}');
    debugPrint('[Backend] Page range: $pageRangeLabel');
    debugPrint('[Backend] Mode: $mode');
    debugPrint('[Backend] summaryLength: $summaryLength');
    debugPrint('[Backend] targetWords: $targetWords');
    debugPrint('[Backend] questionCount: ${_getQuestionCount(toPage - fromPage + 1)}');

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/generate-result'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'extractedText': extractedText,
              'outputType': outputType,
              'summaryLength': summaryLength,
              'outputLanguage': outputLanguage,
              'fileName': fileName,
              'fromPage': fromPage,
              'toPage': toPage,
              'totalPages': totalPages,
              'pageRangeLabel': pageRangeLabel,
              'mode': mode,
              'targetWords': targetWords,
              'targetPages': targetPages,
              'questionCount': _getQuestionCount(toPage - fromPage + 1),
            }),
          )
          .timeout(const Duration(seconds: 180));

      debugPrint('[Backend] Response status: ${response.statusCode}');
      debugPrint('[Backend] Response body length: ${response.body.length}');

      if (response.statusCode != 200) {
        debugPrint(
          '[Backend] Error response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          debugPrint('[Backend] Success - parsing result');

          // Parse Q&A if present
          List<QuestionAnswer>? qaList;
          if (data['questionsAndAnswers'] != null) {
            qaList = (data['questionsAndAnswers'] as List)
                .map(
                  (qa) => QuestionAnswer(
                    question: qa['question'] ?? '',
                    answer: qa['answer'] ?? '',
                  ),
                )
                .toList();
          }

          // Determine result type
          final resultTypeStr = data['resultType'] ?? 'summaryOnly';
          GeneratedResultType resultType;
          switch (resultTypeStr) {
            case 'questionsOnly':
              resultType = GeneratedResultType.questionsOnly;
              break;
            case 'summaryAndQuestions':
              resultType = GeneratedResultType.summaryAndQuestions;
              break;
            default:
              resultType = GeneratedResultType.summaryOnly;
          }

          // Debug logs for parsed data
          final summary = data['summary'] ?? '';
          debugPrint('[Backend] Parsed questions count: ${qaList?.length ?? 0}');
          debugPrint('[Backend] Parsed summary length: ${summary.length}');
          if (qaList != null) {
            for (int i = 0; i < qaList.length; i++) {
              debugPrint('[QA][$i] Q: ${qaList[i].question}');
              debugPrint('[QA][$i] A: ${qaList[i].answer}');
            }
          }

          return GeneratedResult(
            success: true,
            resultType: resultType,
            generatedAt: DateTime.now(),
            summary: data['summary'],
            questionsAndAnswers: qaList,
          );
        } else {
          debugPrint('[Backend] Error in response: ${data['error']}');
          return null;
        }
      } else {
        debugPrint('[Backend] HTTP error: ${response.statusCode}');
        return null;
      }
    } on SocketException catch (e) {
      debugPrint('[Backend] Connection error: $e');
      debugPrint('[Backend] Is the backend server running?');
      return null;
    } on http.ClientException catch (e) {
      debugPrint('[Backend] Client error: $e');
      return null;
    } catch (e) {
      debugPrint('[Backend] Unexpected error: $e');
      return null;
    }
  }

  /// Attempts to generate result using Firebase Cloud Functions.
  ///
  /// Returns null if Firebase is not available or call fails.
  Future<GeneratedResult?> _tryFirebaseGeneration(
    SelectedFileInfo fileInfo,
    SummaryOptions options,
  ) async {
    // Check if Firebase is available
    if (!_firebaseService.isAvailable) {
      final initialized = await _firebaseService.initialize();
      if (!initialized) {
        debugPrint('[Firebase] Not configured, skipping');
        return null;
      }
    }

    // Map output type index to string
    final outputTypeMap = {0: 'summary', 1: 'qa', 2: 'both'};

    // Map length index to string
    final lengthMap = {0: 'short', 1: 'medium', 2: 'long', 3: 'custom'};

    final outputType = outputTypeMap[options.outputTypeIndex] ?? 'summary';
    final summaryLength = lengthMap[options.lengthIndex] ?? 'medium';

    try {
      final result = await _firebaseService.generateAiResult(
        extractedText: fileInfo.extractedText!,
        outputType: outputType,
        summaryLength: summaryLength,
        fileName: fileInfo.fileName,
      );

      return result;
    } on FirebaseNotConfiguredException catch (e) {
      debugPrint('[Firebase] Not configured: $e');
      return null;
    } on FunctionNotDeployedException catch (e) {
      debugPrint('[Firebase] Function not deployed: $e');
      return null;
    } on FunctionCallException catch (e) {
      debugPrint('[Firebase] Function call failed: $e');
      return null;
    } catch (e) {
      debugPrint('[Firebase] Unexpected error: $e');
      return null;
    }
  }

  /// Generates a local dummy result for testing when all backends fail.
  ///
  /// This ensures the app works during development without backend setup.
  Future<GeneratedResult> _generateLocalDummyResult(
    SelectedFileInfo fileInfo,
    SummaryOptions options,
  ) async {
    // Simulate network delay (2 seconds)
    await Future.delayed(const Duration(seconds: 2));

    try {
      switch (options.outputTypeIndex) {
        case 0:
          // Summary only
          return GeneratedResult.summaryOnly(
            summary: _generateDummySummary(options.lengthIndex),
          );

        case 1:
          // Questions and Answers only
          return GeneratedResult.questionsOnly(
            questionsAndAnswers: _generateDummyQuestions(),
          );

        case 2:
          // Summary + Questions and Answers
          return GeneratedResult.summaryAndQuestions(
            summary: _generateDummySummary(options.lengthIndex),
            questionsAndAnswers: _generateDummyQuestions(),
          );

        default:
          return GeneratedResult.summaryOnly(
            summary: _generateDummySummary(options.lengthIndex),
          );
      }
    } catch (e) {
      return GeneratedResult.error(
        'حدث خطأ أثناء إنشاء النتيجة. يرجى المحاولة مرة أخرى.',
      );
    }
  }

  /// Generates a dummy summary based on length preference.
  String _generateDummySummary(int lengthIndex) {
    final lengthLabels = ['قصير', 'متوسط', 'طويل', 'مخصص'];
    final lengthLabel = lengthIndex < lengthLabels.length
        ? lengthLabels[lengthIndex]
        : 'متوسط';

    return '''
ملخص تجريبي محلي ($lengthLabel)

هذا ملخص تجريبي تم إنشاؤه محلياً لأن الخادم الخلفي غير متصل.

لتفعيل الملخصات الحقيقية باستخدام الذكاء الاصطناعي:
1. شغّل الخادم المحلي: cd local_backend && npm run dev
2. تأكد من إضافة مفتاح OpenRouter في ملف .env

النقاط الرئيسية:
• تم استخراج النص من الملف بنجاح
• تم تحديد نوع المخرجات المطلوب
• تم تحديد طول الملخص: $lengthLabel

سيقوم النظام بعد تشغيل الخادم بتحليل المحتوى المستخرج وإنشاء ملخص شامل يغطي جميع النقاط الرئيسية في الوثيقة باستخدام الذكاء الاصطناعي.
''';
  }

  /// Generates dummy questions and answers.
  List<QuestionAnswer> _generateDummyQuestions() {
    return const [
      QuestionAnswer(
        question: 'ما هو الموضوع الرئيسي للوثيقة؟',
        answer:
            'هذا سؤال تجريبي محلي. بعد تشغيل الخادم، سيتم إنشاء أسئلة حقيقية بناءً على محتوى الملف.',
      ),
      QuestionAnswer(
        question: 'ما هي النقاط الرئيسية المذكورة؟',
        answer:
            'سيتم تحليل النص المستخرج وإنشاء قائمة بالنقاط الرئيسية تلقائياً باستخدام الذكاء الاصطناعي.',
      ),
      QuestionAnswer(
        question: 'ما هي الاستنتاجات النهائية؟',
        answer:
            'سيقوم النظام باستخراج الاستنتاجات والتوصيات من الوثيقة وعرضها بشكل منظم.',
      ),
      QuestionAnswer(
        question: 'ما هي المصطلحات المهمة في الوثيقة؟',
        answer: 'سيتم تحديد المصطلحات والمفاهيم الرئيسية وشرحها بشكل مبسط.',
      ),
      QuestionAnswer(
        question: 'كيف يمكن تطبيق هذه المعلومات؟',
        answer:
            'سيوفر النظام اقتراحات عملية لكيفية الاستفادة من المعلومات الموجودة في الوثيقة.',
      ),
    ];
  }
}
