import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_plan.dart';

/// Design-only mode flag.
/// When true:
/// - All quota checks are bypassed (checkCanGenerate always returns success)
/// - No usage is counted (incrementUsageAfterSuccess is a no-op)
/// - Plans page and paywall UI remain available but are never shown automatically
/// - All users can use all features without any blocking
///
/// Set to false when ready to enable real subscription logic.
const bool designOnlyMode = true;

/// Service for managing user subscriptions and usage limits.
class SubscriptionService {
  static SubscriptionService? _instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  SubscriptionService._();

  static SubscriptionService get instance {
    _instance ??= SubscriptionService._();
    return _instance!;
  }

  /// Get subscription document reference for a user
  DocumentReference _getSubscriptionRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('subscription').doc('current');
  }

  /// Get current plan for a user
  /// Returns free plan if no subscription exists
  Future<UserPlan> getCurrentPlan(String uid) async {
    debugPrint('[Subscription] Getting current plan for user: $uid');

    try {
      final doc = await _getSubscriptionRef(uid).get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('[Subscription] No subscription found, returning free plan');
        return UserPlan.free();
      }

      final plan = UserPlan.fromFirestore(doc.data() as Map<String, dynamic>);
      debugPrint('[Subscription] Current plan: ${plan.planId}');
      debugPrint('[Subscription] usedToday: ${plan.usedToday}, dailyLimit: ${plan.dailyLimit}');
      debugPrint('[Subscription] usedThisMonth: ${plan.usedThisMonth}, monthlyLimit: ${plan.monthlyLimit}');
      debugPrint('[Subscription] maxPagesPerRequest: ${plan.maxPagesPerRequest}');

      // Check if we need to reset usage
      final updatedPlan = await _checkAndResetUsage(uid, plan);
      return updatedPlan;
    } catch (e) {
      debugPrint('[Subscription] Error getting plan: $e');
      return UserPlan.free();
    }
  }

  /// Create free subscription for a new user
  Future<void> createFreePlanForNewUser(String uid) async {
    debugPrint('[Subscription] Creating free plan for new user: $uid');

    try {
      final ref = _getSubscriptionRef(uid);
      final doc = await ref.get();

      if (doc.exists) {
        debugPrint('[Subscription] Subscription already exists, skipping creation');
        return;
      }

      final freePlan = UserPlan.free();
      await ref.set(freePlan.toFirestore());
      debugPrint('[Subscription] Free plan created successfully');
    } catch (e) {
      debugPrint('[Subscription] Error creating free plan: $e');
      rethrow;
    }
  }

  /// Check if user can generate with the given parameters
  ///
  /// In design-only mode, this always returns success to allow all users
  /// to use all features without any blocking.
  Future<UsageCheckResult> checkCanGenerate({
    required String uid,
    required int selectedPageCount,
    required String outputType,
    required String summaryLength,
  }) async {
    debugPrint('[Subscription] Checking if user can generate');
    debugPrint('[Subscription] selectedPageCount: $selectedPageCount');
    debugPrint('[Subscription] outputType: $outputType');
    debugPrint('[Subscription] summaryLength: $summaryLength');

    // Design-only mode: always allow, no blocking
    if (designOnlyMode) {
      debugPrint('[Subscription] DESIGN MODE: All features allowed, no limits enforced');
      return UsageCheckResult.success();
    }

    try {
      final plan = await getCurrentPlan(uid);

      // Check daily limit (for free plan)
      if (plan.dailyLimit > 0 && plan.usedToday >= plan.dailyLimit) {
        debugPrint('[Subscription] BLOCKED: Daily limit reached');
        return UsageCheckResult.dailyLimitReached();
      }

      // Check monthly limit (for paid plans)
      if (plan.monthlyLimit > 0 && plan.usedThisMonth >= plan.monthlyLimit) {
        debugPrint('[Subscription] BLOCKED: Monthly limit reached');
        return UsageCheckResult.monthlyLimitReached();
      }

      // Check page limit
      if (selectedPageCount > plan.maxPagesPerRequest) {
        debugPrint('[Subscription] BLOCKED: Page limit exceeded (${plan.maxPagesPerRequest} max)');
        return UsageCheckResult.pageLimitExceeded(plan.maxPagesPerRequest);
      }

      // Check if questions are allowed
      final wantsQuestions = outputType == 'qa' || outputType == 'both' ||
          outputType == 'questionsOnly' || outputType == 'summaryAndQuestions';
      if (wantsQuestions && !plan.canUseQuestions) {
        debugPrint('[Subscription] BLOCKED: Questions not allowed');
        return UsageCheckResult.questionsNotAllowed();
      }

      // Check if long summary is allowed
      if (summaryLength == 'long' && !plan.canUseLongSummary) {
        debugPrint('[Subscription] BLOCKED: Long summary not allowed');
        return UsageCheckResult.longSummaryNotAllowed();
      }

      debugPrint('[Subscription] ALLOWED: All checks passed');
      return UsageCheckResult.success();
    } catch (e) {
      debugPrint('[Subscription] Error checking limits: $e');
      // Allow on error to not block users
      return UsageCheckResult.success();
    }
  }

  /// Increment usage after successful generation
  ///
  /// In design-only mode, this is a no-op (no usage is counted).
  Future<void> incrementUsageAfterSuccess(String uid) async {
    // Design-only mode: don't count usage
    if (designOnlyMode) {
      debugPrint('[Subscription] DESIGN MODE: Skipping usage increment');
      return;
    }

    debugPrint('[Subscription] Incrementing usage for user: $uid');

    try {
      final ref = _getSubscriptionRef(uid);

      await ref.update({
        'usedToday': FieldValue.increment(1),
        'usedThisMonth': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[Subscription] Usage incremented successfully');
    } catch (e) {
      debugPrint('[Subscription] Error incrementing usage: $e');
      // Don't rethrow - usage increment failure shouldn't break the app
    }
  }

  /// Check and reset usage if needed (daily or monthly)
  Future<UserPlan> _checkAndResetUsage(String uid, UserPlan plan) async {
    final today = UserPlan.todayFormatted;
    final currentMonth = UserPlan.currentMonthFormatted;

    bool needsUpdate = false;
    int newUsedToday = plan.usedToday;
    int newUsedThisMonth = plan.usedThisMonth;
    String newLastResetDate = plan.lastResetDate;

    // Check if we need to reset daily usage
    if (plan.lastResetDate != today) {
      debugPrint('[Subscription] Resetting daily usage (last reset: ${plan.lastResetDate}, today: $today)');
      newUsedToday = 0;
      newLastResetDate = today;
      needsUpdate = true;
    }

    // Check if we need to reset monthly usage
    final lastResetMonth = plan.lastResetDate.length >= 7 ? plan.lastResetDate.substring(0, 7) : '';
    if (lastResetMonth != currentMonth) {
      debugPrint('[Subscription] Resetting monthly usage (last reset month: $lastResetMonth, current: $currentMonth)');
      newUsedThisMonth = 0;
      needsUpdate = true;
    }

    if (needsUpdate) {
      try {
        await _getSubscriptionRef(uid).update({
          'usedToday': newUsedToday,
          'usedThisMonth': newUsedThisMonth,
          'lastResetDate': newLastResetDate,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('[Subscription] Usage reset successfully');
      } catch (e) {
        debugPrint('[Subscription] Error resetting usage: $e');
      }

      return plan.copyWith(
        usedToday: newUsedToday,
        usedThisMonth: newUsedThisMonth,
        lastResetDate: newLastResetDate,
      );
    }

    return plan;
  }

  /// Reset daily usage if needed (called on app start)
  Future<void> resetDailyUsageIfNeeded(String uid) async {
    debugPrint('[Subscription] Checking if daily reset needed for user: $uid');

    try {
      final plan = await getCurrentPlan(uid);
      // getCurrentPlan already handles the reset
      debugPrint('[Subscription] Daily reset check complete. Current usedToday: ${plan.usedToday}');
    } catch (e) {
      debugPrint('[Subscription] Error in daily reset check: $e');
    }
  }

  /// Reset monthly usage if needed (called on app start)
  Future<void> resetMonthlyUsageIfNeeded(String uid) async {
    debugPrint('[Subscription] Checking if monthly reset needed for user: $uid');

    try {
      final plan = await getCurrentPlan(uid);
      // getCurrentPlan already handles the reset
      debugPrint('[Subscription] Monthly reset check complete. Current usedThisMonth: ${plan.usedThisMonth}');
    } catch (e) {
      debugPrint('[Subscription] Error in monthly reset check: $e');
    }
  }

  /// Stream current plan for real-time updates
  Stream<UserPlan> watchCurrentPlan(String uid) {
    return _getSubscriptionRef(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return UserPlan.free();
      }
      return UserPlan.fromFirestore(doc.data() as Map<String, dynamic>);
    });
  }

  /// Get plan details for display
  static List<PlanInfo> getAvailablePlans() {
    return [
      PlanInfo(
        planId: 'free',
        nameArabic: 'الخطة المجانية',
        priceArabic: 'مجاناً',
        features: [
          '3 تلخيصات يومياً',
          'حد أقصى 10 صفحات',
          'ملخص قصير فقط',
          'السجل الأساسي',
        ],
        isCurrentPlan: true, // Will be updated based on user's actual plan
      ),
      PlanInfo(
        planId: 'basic',
        nameArabic: 'الخطة الأساسية',
        priceArabic: 'قريباً',
        features: [
          '100 تلخيص شهرياً',
          'حد أقصى 50 صفحة',
          'ملخص + أسئلة وأجوبة',
          'تصدير PDF',
          'السجل الكامل',
        ],
        isCurrentPlan: false,
      ),
      PlanInfo(
        planId: 'pro',
        nameArabic: 'الخطة الاحترافية',
        priceArabic: 'قريباً',
        features: [
          '500 تلخيص شهرياً',
          'حد أقصى 200 صفحة',
          'ملخصات طويلة',
          'تحديد نطاق الصفحات',
          'أسئلة وأجوبة متقدمة',
          'أولوية في المعالجة',
        ],
        isCurrentPlan: false,
        isPriority: true,
      ),
    ];
  }
}

/// Plan information for display
class PlanInfo {
  final String planId;
  final String nameArabic;
  final String priceArabic;
  final List<String> features;
  final bool isCurrentPlan;
  final bool isPriority;

  const PlanInfo({
    required this.planId,
    required this.nameArabic,
    required this.priceArabic,
    required this.features,
    this.isCurrentPlan = false,
    this.isPriority = false,
  });

  PlanInfo copyWith({bool? isCurrentPlan}) {
    return PlanInfo(
      planId: planId,
      nameArabic: nameArabic,
      priceArabic: priceArabic,
      features: features,
      isCurrentPlan: isCurrentPlan ?? this.isCurrentPlan,
      isPriority: isPriority,
    );
  }
}
