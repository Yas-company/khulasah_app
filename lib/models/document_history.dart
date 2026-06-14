import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a document processing history entry.
///
/// Stored in Firestore for logged-in users to track their processed documents.
class DocumentHistory {
  final String? id;
  final String fileName;
  final int fileSize;
  final int extractedTextLength;
  final String outputType;
  final String summaryLength;
  final String? generatedSummary;
  final List<Map<String, String>>? questionsAndAnswers;
  final DateTime createdAt;

  DocumentHistory({
    this.id,
    required this.fileName,
    required this.fileSize,
    required this.extractedTextLength,
    required this.outputType,
    required this.summaryLength,
    this.generatedSummary,
    this.questionsAndAnswers,
    required this.createdAt,
  });

  /// Create from Firestore document
  factory DocumentHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse questionsAndAnswers
    List<Map<String, String>>? qaList;
    if (data['questionsAndAnswers'] != null) {
      qaList = (data['questionsAndAnswers'] as List)
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
    }

    return DocumentHistory(
      id: doc.id,
      fileName: data['fileName'] ?? '',
      fileSize: data['fileSize'] ?? 0,
      extractedTextLength: data['extractedTextLength'] ?? 0,
      outputType: data['outputType'] ?? 'summary',
      summaryLength: data['summaryLength'] ?? 'medium',
      generatedSummary: data['generatedSummary'],
      questionsAndAnswers: qaList,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'fileName': fileName,
      'fileSize': fileSize,
      'extractedTextLength': extractedTextLength,
      'outputType': outputType,
      'summaryLength': summaryLength,
      'generatedSummary': generatedSummary,
      'questionsAndAnswers': questionsAndAnswers,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Check if has summary
  bool get hasSummary => generatedSummary != null && generatedSummary!.isNotEmpty;

  /// Check if has Q&A
  bool get hasQuestionsAndAnswers =>
      questionsAndAnswers != null && questionsAndAnswers!.isNotEmpty;

  /// Get Arabic label for output type
  String get outputTypeLabel {
    switch (outputType) {
      case 'summary':
        return 'ملخص';
      case 'qa':
        return 'سؤال وجواب';
      case 'both':
        return 'ملخص + أسئلة';
      default:
        return 'ملخص';
    }
  }

  /// Get Arabic label for summary length
  String get summaryLengthLabel {
    switch (summaryLength) {
      case 'short':
        return 'قصير';
      case 'medium':
        return 'متوسط';
      case 'long':
        return 'طويل';
      case 'custom':
        return 'مخصص';
      default:
        return 'متوسط';
    }
  }

  /// Get formatted date string
  String get formattedDate {
    return '${createdAt.year}/${_padZero(createdAt.month)}/${_padZero(createdAt.day)}';
  }

  /// Get formatted date and time string
  String get formattedDateTime {
    return '$formattedDate ${_padZero(createdAt.hour)}:${_padZero(createdAt.minute)}';
  }

  /// Get formatted file size
  String get fileSizeFormatted {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String _padZero(int value) => value.toString().padLeft(2, '0');
}
