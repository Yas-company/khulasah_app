class SummaryOptions {
  final int outputTypeIndex;
  final int lengthIndex;
  final int outputLanguageIndex;

  const SummaryOptions({
    required this.outputTypeIndex,
    required this.lengthIndex,
    this.outputLanguageIndex = 0,
  });

  String get outputTypeLabel {
    switch (outputTypeIndex) {
      case 0:
        return 'ملخص فقط';
      case 1:
        return 'سؤال وجواب';
      case 2:
        return 'ملخص + سؤال وجواب';
      default:
        return 'ملخص فقط';
    }
  }

  String get lengthLabel {
    switch (lengthIndex) {
      case 0:
        return 'صفحة واحدة';
      case 1:
        return '5 صفحات';
      case 2:
        return '10 صفحات';
      case 3:
        return 'مخصص';
      default:
        return 'صفحة واحدة';
    }
  }

  /// Language code for backend (ar/en)
  String get outputLanguageCode {
    switch (outputLanguageIndex) {
      case 0:
        return 'ar';
      case 1:
        return 'en';
      default:
        return 'ar';
    }
  }

  /// Language label for UI display
  String get outputLanguageLabel {
    switch (outputLanguageIndex) {
      case 0:
        return 'العربية';
      case 1:
        return 'English';
      default:
        return 'العربية';
    }
  }
}
