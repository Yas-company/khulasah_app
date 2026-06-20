class SummaryOptions {
  final int outputTypeIndex;
  final int lengthIndex;
  final int outputLanguageIndex;
  final int? customTargetWords;
  final int? customTargetPages;

  const SummaryOptions({
    required this.outputTypeIndex,
    required this.lengthIndex,
    this.outputLanguageIndex = 0,
    this.customTargetWords,
    this.customTargetPages,
  });

  String get summaryLength {
    switch (lengthIndex) {
      case 0:
        return 'onePage';
      case 1:
        return 'fivePages';
      case 2:
        return 'tenPages';
      case 3:
        return 'custom';
      default:
        return 'onePage';
    }
  }

  int get targetWords {
    switch (lengthIndex) {
      case 0:
        return 600;
      case 1:
        return 2500;
      case 2:
        return 5000;
      case 3:
        return customTargetWords ?? 1000;
      default:
        return 600;
    }
  }

  int get targetPages {
    switch (lengthIndex) {
      case 0:
        return 1;
      case 1:
        return 5;
      case 2:
        return 10;
      case 3:
        return customTargetPages ?? 2;
      default:
        return 1;
    }
  }

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

  String get lengthDescription {
    switch (lengthIndex) {
      case 0:
        return 'ملخص مختصر';
      case 1:
        return 'ملخص مفصل';
      case 2:
        return 'ملخص عميق وموسع';
      case 3:
        return 'حدد الطول المناسب لك';
      default:
        return 'ملخص مختصر';
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
