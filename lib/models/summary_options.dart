class SummaryOptions {
  final int outputTypeIndex;
  final int lengthIndex;

  const SummaryOptions({
    required this.outputTypeIndex,
    required this.lengthIndex,
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
}
