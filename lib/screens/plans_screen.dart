import 'package:flutter/material.dart';

import '../models/user_plan.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';

/// Screen displaying available subscription plans.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  UserPlan? _currentPlan;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final uid = AuthService.instance.userId;
    if (uid != null) {
      final plan = await SubscriptionService.instance.getCurrentPlan(uid);
      if (mounted) {
        setState(() {
          _currentPlan = plan;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentPlan = UserPlan.free();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'الخطط والأسعار',
            style: AppTextStyles.headlineSmall,
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Text(
                        'اختر الخطة المناسبة لك',
                        style: AppTextStyles.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'يمكنك الترقية في أي وقت للحصول على ميزات أكثر',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Plan Cards
                      _buildPlanCard(
                        planId: 'free',
                        name: 'الخطة المجانية',
                        price: 'مجاناً',
                        features: [
                          '3 تلخيصات يومياً',
                          'حد أقصى 10 صفحات',
                          'ملخص قصير فقط',
                          'السجل الأساسي',
                        ],
                        isCurrentPlan: _currentPlan?.planId == 'free',
                        accentColor: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),

                      _buildPlanCard(
                        planId: 'basic',
                        name: 'الخطة الأساسية',
                        price: 'قريباً',
                        features: [
                          '100 تلخيص شهرياً',
                          'حد أقصى 50 صفحة',
                          'ملخص + أسئلة وأجوبة',
                          'تصدير PDF',
                          'السجل الكامل',
                        ],
                        isCurrentPlan: _currentPlan?.planId == 'basic',
                        accentColor: AppColors.primary,
                        isPopular: true,
                      ),
                      const SizedBox(height: 16),

                      _buildPlanCard(
                        planId: 'pro',
                        name: 'الخطة الاحترافية',
                        price: 'قريباً',
                        features: [
                          '500 تلخيص شهرياً',
                          'حد أقصى 200 صفحة',
                          'ملخصات طويلة',
                          'تحديد نطاق الصفحات',
                          'أسئلة وأجوبة متقدمة',
                          'أولوية في المعالجة',
                        ],
                        isCurrentPlan: _currentPlan?.planId == 'pro',
                        accentColor: AppColors.accent,
                        isPriority: true,
                      ),
                      const SizedBox(height: 32),

                      // Note
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'الاشتراكات قادمة قريباً! سنقوم بإعلامك عند توفرها.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String planId,
    required String name,
    required String price,
    required List<String> features,
    required bool isCurrentPlan,
    required Color accentColor,
    bool isPopular = false,
    bool isPriority = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentPlan ? accentColor : AppColors.border,
          width: isCurrentPlan ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan name and badge row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppTextStyles.titleLarge.copyWith(
                          color: accentColor,
                        ),
                      ),
                    ),
                    if (isPriority)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'أولوية',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Price
                Text(
                  price,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Features
                ...features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),

                // Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan
                        ? null
                        : () {
                            // Show coming soon message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'الاشتراكات قادمة قريباً!',
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isCurrentPlan ? AppColors.surface : accentColor,
                      foregroundColor:
                          isCurrentPlan ? accentColor : Colors.white,
                      disabledBackgroundColor: AppColors.surface,
                      disabledForegroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isCurrentPlan
                            ? BorderSide(color: accentColor)
                            : BorderSide.none,
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isCurrentPlan ? 'خطتك الحالية' : 'قريباً',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isCurrentPlan ? accentColor : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Popular badge
          if (isPopular)
            Positioned(
              top: 0,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  'الأكثر شيوعاً',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
