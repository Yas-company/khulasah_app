import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/generated_result.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import 'firebase_functions_service.dart';

/// Backend service that handles communication with AI/summarization services.
///
/// This service uses a priority-based approach:
/// 1. Try local Node.js backend (OpenRouter) first
/// 2. If local backend fails, try Firebase Cloud Functions
/// 3. If all backends fail, use local dummy generation
///
/// SECURITY NOTES:
/// - Never store API keys in Flutter/Dart code
/// - All AI API calls go through backend services
/// - The OpenRouter API key is stored in the local backend's .env file
class BackendService {
  final FirebaseFunctionsService _firebaseService =
      FirebaseFunctionsService.instance;

  /// Local backend URL for iOS Simulator
  /// For physical device, use your computer's IP address
  static const String _localBackendUrl = 'http://127.0.0.1:3000';

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
  }) async {
    // Validate input first
    if (!fileInfo.hasExtractedText) {
      return GeneratedResult.error(
        'لا يوجد نص مستخرج من الملف للمعالجة',
      );
    }

    // Try local Node.js backend first (OpenRouter)
    debugPrint('[Backend] Trying local backend...');
    try {
      final result = await _tryLocalBackend(fileInfo, options);
      if (result != null) {
        debugPrint('[Backend] Local backend success');
        return result;
      }
    } catch (e) {
      debugPrint('[Backend] Local backend failed: $e');
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

    // Fallback to local dummy generation
    debugPrint('[Backend] Using local dummy fallback...');
    final result = await _generateLocalDummyResult(fileInfo, options);
    debugPrint('[Backend] Local dummy result generated');
    return result;
  }

  /// Attempts to generate result using local Node.js backend.
  ///
  /// Returns null if local backend is not available or call fails.
  Future<GeneratedResult?> _tryLocalBackend(
    SelectedFileInfo fileInfo,
    SummaryOptions options,
  ) async {
    // Map output type index to string
    final outputTypeMap = {
      0: 'summaryOnly',
      1: 'questionsOnly',
      2: 'summaryAndQuestions',
    };

    // Map length index to string
    final lengthMap = {
      0: 'short',
      1: 'medium',
      2: 'long',
      3: 'medium', // custom defaults to medium
    };

    final outputType = outputTypeMap[options.outputTypeIndex] ?? 'summaryOnly';
    final summaryLength = lengthMap[options.lengthIndex] ?? 'medium';

    debugPrint('[LocalBackend] Calling $_localBackendUrl/generate-result');
    debugPrint('[LocalBackend] Output type: $outputType, Length: $summaryLength');

    try {
      final response = await http
          .post(
            Uri.parse('$_localBackendUrl/generate-result'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'extractedText': fileInfo.extractedText,
              'outputType': outputType,
              'summaryLength': summaryLength,
              'fileName': fileInfo.fileName,
            }),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('[LocalBackend] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          debugPrint('[LocalBackend] Success - parsing result');

          // Parse Q&A if present
          List<QuestionAnswer>? qaList;
          if (data['questionsAndAnswers'] != null) {
            qaList = (data['questionsAndAnswers'] as List)
                .map((qa) => QuestionAnswer(
                      question: qa['question'] ?? '',
                      answer: qa['answer'] ?? '',
                    ))
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

          return GeneratedResult(
            success: true,
            resultType: resultType,
            generatedAt: DateTime.now(),
            summary: data['summary'],
            questionsAndAnswers: qaList,
          );
        } else {
          debugPrint('[LocalBackend] Error in response: ${data['error']}');
          return null;
        }
      } else {
        debugPrint('[LocalBackend] HTTP error: ${response.statusCode}');
        return null;
      }
    } on SocketException catch (e) {
      debugPrint('[LocalBackend] Connection error: $e');
      debugPrint('[LocalBackend] Is the backend server running?');
      return null;
    } on http.ClientException catch (e) {
      debugPrint('[LocalBackend] Client error: $e');
      return null;
    } catch (e) {
      debugPrint('[LocalBackend] Unexpected error: $e');
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
    final outputTypeMap = {
      0: 'summary',
      1: 'qa',
      2: 'both',
    };

    // Map length index to string
    final lengthMap = {
      0: 'short',
      1: 'medium',
      2: 'long',
      3: 'custom',
    };

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
        answer: 'هذا سؤال تجريبي محلي. بعد تشغيل الخادم، سيتم إنشاء أسئلة حقيقية بناءً على محتوى الملف.',
      ),
      QuestionAnswer(
        question: 'ما هي النقاط الرئيسية المذكورة؟',
        answer: 'سيتم تحليل النص المستخرج وإنشاء قائمة بالنقاط الرئيسية تلقائياً باستخدام الذكاء الاصطناعي.',
      ),
      QuestionAnswer(
        question: 'ما هي الاستنتاجات النهائية؟',
        answer: 'سيقوم النظام باستخراج الاستنتاجات والتوصيات من الوثيقة وعرضها بشكل منظم.',
      ),
      QuestionAnswer(
        question: 'ما هي المصطلحات المهمة في الوثيقة؟',
        answer: 'سيتم تحديد المصطلحات والمفاهيم الرئيسية وشرحها بشكل مبسط.',
      ),
      QuestionAnswer(
        question: 'كيف يمكن تطبيق هذه المعلومات؟',
        answer: 'سيوفر النظام اقتراحات عملية لكيفية الاستفادة من المعلومات الموجودة في الوثيقة.',
      ),
    ];
  }
}
