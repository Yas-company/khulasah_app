import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/generated_result.dart';

/// Service for calling Firebase Cloud Functions.
///
/// This service handles communication with the Firebase Cloud Functions backend
/// which will process AI-powered summarization and Q&A generation.
///
/// SETUP REQUIRED:
/// ===============
/// Before this service works, you must:
/// 1. Run: firebase login
/// 2. Run: flutterfire configure
/// 3. Run: firebase deploy --only functions
///
/// The service gracefully handles cases where Firebase is not configured.
class FirebaseFunctionsService {
  static FirebaseFunctionsService? _instance;
  FirebaseFunctions? _functions;
  bool _isInitialized = false;
  bool _initializationFailed = false;

  FirebaseFunctionsService._();

  /// Gets the singleton instance of the service.
  static FirebaseFunctionsService get instance {
    _instance ??= FirebaseFunctionsService._();
    return _instance!;
  }

  /// Checks if Firebase is properly initialized.
  bool get isAvailable => _isInitialized && !_initializationFailed;

  /// Initializes Firebase if not already initialized.
  ///
  /// Returns true if initialization was successful, false otherwise.
  /// This method is safe to call multiple times.
  Future<bool> initialize() async {
    if (_isInitialized) return !_initializationFailed;
    if (_initializationFailed) return false;

    try {
      // Check if Firebase is already initialized
      if (Firebase.apps.isEmpty) {
        // Firebase not configured - this is expected during development
        // without firebase_options.dart
        _initializationFailed = true;
        _isInitialized = true;
        return false;
      }

      _functions = FirebaseFunctions.instance;

      // Optionally use emulator for local development
      // Uncomment the line below to use Firebase emulator
      // _functions!.useFunctionsEmulator('localhost', 5001);

      _isInitialized = true;
      return true;
    } catch (e) {
      _initializationFailed = true;
      _isInitialized = true;
      return false;
    }
  }

  /// Generates AI result by calling Firebase Cloud Function.
  ///
  /// Parameters:
  /// - [extractedText]: The text extracted from the PDF
  /// - [outputType]: Type of output (summary, qa, both)
  /// - [summaryLength]: Preferred length of summary
  /// - [fileName]: Original file name for context
  ///
  /// Returns:
  /// A [GeneratedResult] containing the AI-generated content.
  ///
  /// Throws:
  /// - [FirebaseNotConfiguredException] if Firebase is not set up
  /// - [FunctionNotDeployedException] if the function is not deployed (not-found, unavailable)
  /// - [FunctionCallException] if the function call fails for other reasons
  Future<GeneratedResult> generateAiResult({
    required String extractedText,
    required String outputType,
    required String summaryLength,
    required String fileName,
  }) async {
    // Ensure Firebase is initialized
    final isReady = await initialize();

    if (!isReady || _functions == null) {
      throw FirebaseNotConfiguredException(
        'Firebase is not configured. Please run flutterfire configure.',
      );
    }

    try {
      // Get reference to the callable function
      final callable = _functions!.httpsCallable(
        'generateResult',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      // Call the function with parameters
      final result = await callable.call<Map<String, dynamic>>({
        'extractedText': extractedText,
        'outputType': outputType,
        'summaryLength': summaryLength,
        'fileName': fileName,
      });

      // Parse the response
      final data = result.data;

      if (data['success'] != true) {
        return GeneratedResult.error(
          data['error'] ?? 'حدث خطأ غير معروف في الخادم',
        );
      }

      // Parse result based on type
      final resultType = data['resultType'] as String? ?? 'summaryOnly';

      switch (resultType) {
        case 'summaryOnly':
          return GeneratedResult.summaryOnly(
            summary: data['summary'] as String? ?? '',
          );

        case 'questionsOnly':
          final qaList = _parseQuestionsAndAnswers(data['questionsAndAnswers']);
          return GeneratedResult.questionsOnly(
            questionsAndAnswers: qaList,
          );

        case 'summaryAndQuestions':
          final qaList = _parseQuestionsAndAnswers(data['questionsAndAnswers']);
          return GeneratedResult.summaryAndQuestions(
            summary: data['summary'] as String? ?? '',
            questionsAndAnswers: qaList,
          );

        default:
          return GeneratedResult.summaryOnly(
            summary: data['summary'] as String? ?? '',
          );
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('FirebaseFunctionsException: code=${e.code}, message=${e.message}');

      // Check for function not deployed errors - these should fallback to local
      if (_isFunctionNotDeployedError(e.code)) {
        debugPrint('Firebase Function not available, using local fallback');
        throw FunctionNotDeployedException(
          'Cloud Function not deployed: ${e.code}',
        );
      }

      // Handle other specific Firebase Functions errors
      String errorMessage;
      switch (e.code) {
        case 'deadline-exceeded':
          errorMessage = 'انتهت مهلة الطلب. يرجى المحاولة مرة أخرى.';
          break;
        case 'resource-exhausted':
          errorMessage = 'تم تجاوز حد الاستخدام. يرجى المحاولة لاحقاً.';
          break;
        case 'invalid-argument':
          errorMessage = 'بيانات غير صالحة. يرجى التحقق من الملف.';
          break;
        default:
          errorMessage = 'حدث خطأ: ${e.message ?? e.code}';
      }

      throw FunctionCallException(errorMessage);
    } catch (e) {
      debugPrint('Firebase function call error: $e');
      // For any other error, treat as function not available
      throw FunctionNotDeployedException(
        'Function call failed: ${e.toString()}',
      );
    }
  }

  /// Checks if the error code indicates function is not deployed
  bool _isFunctionNotDeployedError(String code) {
    return code == 'not-found' ||
        code == 'NOT_FOUND' ||
        code == 'unavailable' ||
        code == 'UNAVAILABLE' ||
        code == 'unimplemented' ||
        code == 'UNIMPLEMENTED' ||
        code == 'internal' ||
        code == 'INTERNAL';
  }

  /// Parses the questions and answers list from the response.
  List<QuestionAnswer> _parseQuestionsAndAnswers(dynamic qaData) {
    if (qaData == null || qaData is! List) {
      return [];
    }

    return qaData
        .map<QuestionAnswer?>((item) {
          if (item is Map<String, dynamic>) {
            return QuestionAnswer(
              question: item['question'] as String? ?? '',
              answer: item['answer'] as String? ?? '',
            );
          }
          return null;
        })
        .whereType<QuestionAnswer>()
        .toList();
  }
}

/// Exception thrown when Firebase is not configured.
class FirebaseNotConfiguredException implements Exception {
  final String message;
  FirebaseNotConfiguredException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when the Cloud Function is not deployed.
/// This should trigger fallback to local generation.
class FunctionNotDeployedException implements Exception {
  final String message;
  FunctionNotDeployedException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when a function call fails for other reasons.
class FunctionCallException implements Exception {
  final String message;
  FunctionCallException(this.message);

  @override
  String toString() => message;
}
