import '../services/pdf_text_service.dart';

class SelectedFileInfo {
  final String fileName;
  final String? filePath;
  final int? fileSize;
  final String? extractedText;
  final TextQuality textQuality;
  final double readableRatio;
  final String? errorMessage;

  /// Total number of pages in the PDF
  final int totalPages;

  /// Selected start page (1-indexed)
  final int selectedFromPage;

  /// Selected end page (1-indexed)
  final int selectedToPage;

  /// Whether user selected custom page range
  final bool useCustomPageRange;

  /// Whether extraction determined that this range needs staged processing.
  final bool requiresLargeProcessing;

  const SelectedFileInfo({
    required this.fileName,
    this.filePath,
    this.fileSize,
    this.extractedText,
    this.textQuality = TextQuality.high,
    this.readableRatio = 1.0,
    this.errorMessage,
    this.totalPages = 0,
    this.selectedFromPage = 1,
    this.selectedToPage = 0,
    this.useCustomPageRange = false,
    this.requiresLargeProcessing = false,
  });

  String get fileSizeFormatted {
    if (fileSize == null) return '';

    final kb = fileSize! / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  bool get hasExtractedText => extractedText != null && extractedText!.isNotEmpty;

  bool get canGenerateSummary => hasExtractedText && textQuality != TextQuality.empty;

  bool get isEmpty => textQuality == TextQuality.empty || !hasExtractedText;

  bool get hasLimitedQuality => textQuality == TextQuality.medium || textQuality == TextQuality.low;

  bool get hasLowQuality => textQuality == TextQuality.low;

  int get extractedTextLength => extractedText?.length ?? 0;

  String get extractedTextLengthFormatted {
    final length = extractedTextLength;

    if (length < 1000) {
      return '$length حرف';
    }

    final thousands = length / 1000;
    return '${thousands.toStringAsFixed(1)} ألف حرف';
  }

  /// Get the effective end page (defaults to totalPages if not set)
  int get effectiveToPage => selectedToPage > 0 ? selectedToPage : totalPages;

  /// Get the actual page range being used
  int get actualFromPage => useCustomPageRange ? selectedFromPage : 1;
  int get actualToPage => useCustomPageRange ? effectiveToPage : totalPages;

  /// Get Arabic label for page range
  String get pageRangeLabel {
    if (!useCustomPageRange || totalPages == 0) {
      return 'كل الصفحات';
    }
    return 'من صفحة $actualFromPage إلى صفحة $actualToPage';
  }

  /// Short page range label for display
  String get pageRangeLabelShort {
    if (!useCustomPageRange || totalPages == 0) {
      return 'كل الصفحات';
    }
    return 'صفحات $actualFromPage-$actualToPage';
  }

  /// Get formatted total pages
  String get totalPagesFormatted => '$totalPages صفحة';

  SelectedFileInfo copyWith({
    String? fileName,
    String? filePath,
    int? fileSize,
    String? extractedText,
    TextQuality? textQuality,
    double? readableRatio,
    String? errorMessage,
    int? totalPages,
    int? selectedFromPage,
    int? selectedToPage,
    bool? useCustomPageRange,
    bool? requiresLargeProcessing,
  }) {
    return SelectedFileInfo(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      extractedText: extractedText ?? this.extractedText,
      textQuality: textQuality ?? this.textQuality,
      readableRatio: readableRatio ?? this.readableRatio,
      errorMessage: errorMessage ?? this.errorMessage,
      totalPages: totalPages ?? this.totalPages,
      selectedFromPage: selectedFromPage ?? this.selectedFromPage,
      selectedToPage: selectedToPage ?? this.selectedToPage,
      useCustomPageRange: useCustomPageRange ?? this.useCustomPageRange,
      requiresLargeProcessing:
          requiresLargeProcessing ?? this.requiresLargeProcessing,
    );
  }
}
