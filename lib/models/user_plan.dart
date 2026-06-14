import 'package:cloud_firestore/cloud_firestore.dart';

/// User subscription plan model.
///
/// Defines plan limits, features, and current usage.
class UserPlan {
  final String planId;
  final String planNameArabic;
  final int dailyLimit;
  final int monthlyLimit;
  final int usedToday;
  final int usedThisMonth;
  final int maxPagesPerRequest;
  final bool canUseQuestions;
  final bool canUseLongSummary;
  final bool canUsePageRange;
  final bool canExportPdf;
  final String lastResetDate; // Format: YYYY-MM-DD
  final DateTime updatedAt;

  const UserPlan({
    required this.planId,
    required this.planNameArabic,
    required this.dailyLimit,
    required this.monthlyLimit,
    required this.usedToday,
    required this.usedThisMonth,
    required this.maxPagesPerRequest,
    required this.canUseQuestions,
    required this.canUseLongSummary,
    required this.canUsePageRange,
    required this.canExportPdf,
    required this.lastResetDate,
    required this.updatedAt,
  });

  /// Free plan defaults
  factory UserPlan.free() {
    final now = DateTime.now();
    return UserPlan(
      planId: 'free',
      planNameArabic: 'الخطة المجانية',
      dailyLimit: 3,
      monthlyLimit: 0, // No monthly limit for free, only daily
      usedToday: 0,
      usedThisMonth: 0,
      maxPagesPerRequest: 10,
      canUseQuestions: false,
      canUseLongSummary: false,
      canUsePageRange: true,
      canExportPdf: true,
      lastResetDate: _formatDate(now),
      updatedAt: now,
    );
  }

  /// Basic plan defaults
  factory UserPlan.basic() {
    final now = DateTime.now();
    return UserPlan(
      planId: 'basic',
      planNameArabic: 'الخطة الأساسية',
      dailyLimit: 0, // No daily limit for basic, only monthly
      monthlyLimit: 100,
      usedToday: 0,
      usedThisMonth: 0,
      maxPagesPerRequest: 50,
      canUseQuestions: true,
      canUseLongSummary: false,
      canUsePageRange: true,
      canExportPdf: true,
      lastResetDate: _formatDate(now),
      updatedAt: now,
    );
  }

  /// Pro plan defaults
  factory UserPlan.pro() {
    final now = DateTime.now();
    return UserPlan(
      planId: 'pro',
      planNameArabic: 'الخطة الاحترافية',
      dailyLimit: 0, // No daily limit for pro, only monthly
      monthlyLimit: 500,
      usedToday: 0,
      usedThisMonth: 0,
      maxPagesPerRequest: 200,
      canUseQuestions: true,
      canUseLongSummary: true,
      canUsePageRange: true,
      canExportPdf: true,
      lastResetDate: _formatDate(now),
      updatedAt: now,
    );
  }

  /// Create from Firestore document
  factory UserPlan.fromFirestore(Map<String, dynamic> data) {
    return UserPlan(
      planId: data['planId'] as String? ?? 'free',
      planNameArabic: data['planNameArabic'] as String? ?? 'الخطة المجانية',
      dailyLimit: data['dailyLimit'] as int? ?? 3,
      monthlyLimit: data['monthlyLimit'] as int? ?? 0,
      usedToday: data['usedToday'] as int? ?? 0,
      usedThisMonth: data['usedThisMonth'] as int? ?? 0,
      maxPagesPerRequest: data['maxPagesPerRequest'] as int? ?? 10,
      canUseQuestions: data['canUseQuestions'] as bool? ?? false,
      canUseLongSummary: data['canUseLongSummary'] as bool? ?? false,
      canUsePageRange: data['canUsePageRange'] as bool? ?? true,
      canExportPdf: data['canExportPdf'] as bool? ?? true,
      lastResetDate: data['lastResetDate'] as String? ?? _formatDate(DateTime.now()),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'planId': planId,
      'planNameArabic': planNameArabic,
      'dailyLimit': dailyLimit,
      'monthlyLimit': monthlyLimit,
      'usedToday': usedToday,
      'usedThisMonth': usedThisMonth,
      'maxPagesPerRequest': maxPagesPerRequest,
      'canUseQuestions': canUseQuestions,
      'canUseLongSummary': canUseLongSummary,
      'canUsePageRange': canUsePageRange,
      'canExportPdf': canExportPdf,
      'lastResetDate': lastResetDate,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Copy with updated values
  UserPlan copyWith({
    String? planId,
    String? planNameArabic,
    int? dailyLimit,
    int? monthlyLimit,
    int? usedToday,
    int? usedThisMonth,
    int? maxPagesPerRequest,
    bool? canUseQuestions,
    bool? canUseLongSummary,
    bool? canUsePageRange,
    bool? canExportPdf,
    String? lastResetDate,
    DateTime? updatedAt,
  }) {
    return UserPlan(
      planId: planId ?? this.planId,
      planNameArabic: planNameArabic ?? this.planNameArabic,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      usedToday: usedToday ?? this.usedToday,
      usedThisMonth: usedThisMonth ?? this.usedThisMonth,
      maxPagesPerRequest: maxPagesPerRequest ?? this.maxPagesPerRequest,
      canUseQuestions: canUseQuestions ?? this.canUseQuestions,
      canUseLongSummary: canUseLongSummary ?? this.canUseLongSummary,
      canUsePageRange: canUsePageRange ?? this.canUsePageRange,
      canExportPdf: canExportPdf ?? this.canExportPdf,
      lastResetDate: lastResetDate ?? this.lastResetDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if user has reached daily limit
  bool get hasReachedDailyLimit {
    if (dailyLimit == 0) return false; // No daily limit
    return usedToday >= dailyLimit;
  }

  /// Check if user has reached monthly limit
  bool get hasReachedMonthlyLimit {
    if (monthlyLimit == 0) return false; // No monthly limit
    return usedThisMonth >= monthlyLimit;
  }

  /// Check if user has reached any limit
  bool get hasReachedLimit => hasReachedDailyLimit || hasReachedMonthlyLimit;

  /// Get remaining daily summaries
  int get remainingToday {
    if (dailyLimit == 0) return -1; // Unlimited
    return (dailyLimit - usedToday).clamp(0, dailyLimit);
  }

  /// Get remaining monthly summaries
  int get remainingThisMonth {
    if (monthlyLimit == 0) return -1; // Unlimited
    return (monthlyLimit - usedThisMonth).clamp(0, monthlyLimit);
  }

  /// Get Arabic usage text for display
  String get usageTextArabic {
    if (dailyLimit > 0) {
      return 'استخدمت $usedToday من $dailyLimit تلخيصات اليوم';
    } else if (monthlyLimit > 0) {
      return 'استخدمت $usedThisMonth من $monthlyLimit تلخيص هذا الشهر';
    }
    return 'استخدام غير محدود';
  }

  /// Check if plan is free
  bool get isFree => planId == 'free';

  /// Check if plan is basic
  bool get isBasic => planId == 'basic';

  /// Check if plan is pro
  bool get isPro => planId == 'pro';

  /// Format date as YYYY-MM-DD
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get today's date formatted
  static String get todayFormatted => _formatDate(DateTime.now());

  /// Get current month formatted (YYYY-MM)
  static String get currentMonthFormatted {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'UserPlan(planId: $planId, usedToday: $usedToday/$dailyLimit, usedThisMonth: $usedThisMonth/$monthlyLimit, maxPages: $maxPagesPerRequest)';
  }
}

/// Result of checking if user can generate
class UsageCheckResult {
  final bool allowed;
  final String? blockedReason;
  final String? blockedReasonArabic;

  const UsageCheckResult({
    required this.allowed,
    this.blockedReason,
    this.blockedReasonArabic,
  });

  factory UsageCheckResult.success() {
    return const UsageCheckResult(allowed: true);
  }

  factory UsageCheckResult.dailyLimitReached() {
    return const UsageCheckResult(
      allowed: false,
      blockedReason: 'Daily limit reached',
      blockedReasonArabic: 'لقد وصلت إلى الحد اليومي المجاني',
    );
  }

  factory UsageCheckResult.monthlyLimitReached() {
    return const UsageCheckResult(
      allowed: false,
      blockedReason: 'Monthly limit reached',
      blockedReasonArabic: 'لقد وصلت إلى الحد الشهري',
    );
  }

  factory UsageCheckResult.pageLimitExceeded(int maxPages) {
    return UsageCheckResult(
      allowed: false,
      blockedReason: 'Page limit exceeded (max $maxPages)',
      blockedReasonArabic: 'خطتك الحالية تسمح بتلخيص $maxPages صفحات كحد أقصى',
    );
  }

  factory UsageCheckResult.questionsNotAllowed() {
    return const UsageCheckResult(
      allowed: false,
      blockedReason: 'Questions not allowed in current plan',
      blockedReasonArabic: 'الأسئلة والأجوبة غير متاحة في خطتك الحالية',
    );
  }

  factory UsageCheckResult.longSummaryNotAllowed() {
    return const UsageCheckResult(
      allowed: false,
      blockedReason: 'Long summary not allowed in current plan',
      blockedReasonArabic: 'الملخص الطويل غير متاح في خطتك الحالية',
    );
  }
}
