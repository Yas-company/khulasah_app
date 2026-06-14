class SelectedFileInfo {
  final String fileName;
  final String? filePath;
  final int? fileSize;
  final String? extractedText;

  const SelectedFileInfo({
    required this.fileName,
    this.filePath,
    this.fileSize,
    this.extractedText,
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

  int get extractedTextLength => extractedText?.length ?? 0;

  String get extractedTextPreview {
    if (!hasExtractedText) return '';

    if (extractedText!.length <= 500) {
      return extractedText!;
    }

    return '${extractedText!.substring(0, 500)}...';
  }

  String get extractedTextLengthFormatted {
    final length = extractedTextLength;

    if (length < 1000) {
      return '$length حرف';
    }

    final thousands = length / 1000;
    return '${thousands.toStringAsFixed(1)} ألف حرف';
  }

  SelectedFileInfo copyWith({
    String? fileName,
    String? filePath,
    int? fileSize,
    String? extractedText,
  }) {
    return SelectedFileInfo(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      extractedText: extractedText ?? this.extractedText,
    );
  }
}
