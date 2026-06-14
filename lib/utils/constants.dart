class AppConstants {
  // App info
  static const String appNameArabic = 'خُلاصة';
  static const String appNameEnglish = 'Khulasah';
  static const String appTagline = 'لخص ملفاتك ومستنداتك بسهولة';

  // Asset paths
  static const String logoIcon = 'assets/images/khulasah_logo_icon_transparent.png';
  static const String logoFullVertical = 'assets/images/khulasah_full_logo_vertical_transparent.png';
  static const String logoFullHorizontal = 'assets/images/khulasah_full_logo_horizontal_transparent.png';
  static const String appIcon = 'assets/images/khulasah_app_icon_1024.png';

  // Dummy data
  static const String dummySummary = '''
هذا ملخص تجريبي للملف الذي تم رفعه. في النسخة النهائية سيتم تحليل محتوى الملف وإنشاء ملخص واضح ومنظم حسب الاختيارات التي حددها المستخدم.
''';

  static const List<Map<String, String>> dummyHistory = [
    {
      'title': 'تقرير العمل.pdf',
      'type': 'ملخص',
      'date': '2026/06/13',
    },
    {
      'title': 'كتاب الإدارة.pdf',
      'type': 'سؤال وجواب',
      'date': '2026/06/10',
    },
    {
      'title': 'ملف تدريبي.pdf',
      'type': 'ملخص + أسئلة',
      'date': '2026/06/08',
    },
  ];
}
