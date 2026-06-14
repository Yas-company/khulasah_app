import 'package:flutter/material.dart';
import '../models/user_plan.dart';
import '../services/app_feedback_service.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/app_logo.dart';
import 'upload_pdf_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'plans_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService.instance;
  final SubscriptionService _subscriptionService = SubscriptionService.instance;
  UserPlan? _currentPlan;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final uid = _authService.userId;
    if (uid != null) {
      final plan = await _subscriptionService.getCurrentPlan(uid);
      if (mounted) {
        setState(() {
          _currentPlan = plan;
        });
      }
    }
  }

  Future<void> _logout() async {
    debugPrint('[HomeScreen] Manual logout button tapped');
    await AppFeedbackService.instance.tap();
    await _authService.signOut();

    if (!mounted) return;

    await AppFeedbackService.instance.success();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسجيل الخروج بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );

    debugPrint('[HomeScreen] Navigating to LoginScreen after logout');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _goToLogin() {
    debugPrint('[HomeScreen] Guest user tapping login button');
    _authService.disableGuestMode();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _authService.isLoggedIn;
    final userEmail = _authService.userEmail;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                _buildHeader(isLoggedIn, userEmail),

                // Main Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Plan Badge & Usage (only show when logged in)
                      if (isLoggedIn && _currentPlan != null)
                        FadeSlideTransition(
                          delay: const Duration(milliseconds: 50),
                          child: _buildPlanUsageCard(),
                        ),

                      if (isLoggedIn && _currentPlan != null)
                        const SizedBox(height: 16),

                      // Hero Card
                      FadeSlideTransition(
                        delay: const Duration(milliseconds: 100),
                        child: _buildHeroCard(),
                      ),

                      const SizedBox(height: 28),

                      // Services Section Title
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'الخدمات',
                          style: AppTextStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Service Cards Grid
                      _buildServiceCards(),

                      const SizedBox(height: 24),

                      // Bottom Info Note
                      FadeSlideTransition(
                        delay: const Duration(milliseconds: 350),
                        child: _buildInfoNote(),
                      ),

                      const SizedBox(height: 24),
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

  Widget _buildHeader(bool isLoggedIn, String? userEmail) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          AppLogo.icon(width: 38, height: 38),
          const SizedBox(width: 10),

          // Welcome Text & Email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مرحباً بك',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isLoggedIn ? (userEmail ?? 'مستخدم') : 'وضع الضيف',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Account/Login Button
          if (isLoggedIn)
            _buildAccountButton(userEmail)
          else
            _buildLoginButton(),
        ],
      ),
    );
  }

  Widget _buildAccountButton(String? userEmail) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          color: AppColors.primary,
          size: 20,
        ),
      ),
      onSelected: (value) {
        if (value == 'logout') {
          _logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الحساب',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                userEmail ?? '',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'logout',
          height: 40,
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Text(
                'تسجيل الخروج',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.error,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return InkWell(
      onTap: _goToLogin,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'دخول',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
            AppColors.secondary,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // App Name with Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'خُلاصة',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Subtitle
          Text(
            'ارفع ملف PDF واحصل على ملخص أو أسئلة وأجوبة خلال ثوانٍ',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.5,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Upload Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UploadPdfScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.upload_file_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'رفع ملف PDF',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCards() {
    return Column(
      children: [
        // First row
        Row(
          children: [
            Expanded(
              child: StaggeredListItem(
                index: 0,
                child: _buildServiceCard(
                  icon: Icons.summarize_rounded,
                  title: 'تلخيص PDF',
                  description: 'ملخص سريع ومنظم',
                  color: AppColors.primary,
                  onTap: () {
                    AppFeedbackService.instance.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UploadPdfScreen()),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StaggeredListItem(
                index: 1,
                child: _buildServiceCard(
                  icon: Icons.quiz_rounded,
                  title: 'سؤال وجواب',
                  description: 'أسئلة من محتوى الملف',
                  color: AppColors.secondary,
                  onTap: () {
                    AppFeedbackService.instance.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UploadPdfScreen()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Second row
        Row(
          children: [
            Expanded(
              child: StaggeredListItem(
                index: 2,
                child: _buildServiceCard(
                  icon: Icons.auto_awesome_rounded,
                  title: 'ملخص + أسئلة',
                  description: 'الملخص والأسئلة معًا',
                  color: AppColors.accent,
                  onTap: () {
                    AppFeedbackService.instance.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UploadPdfScreen()),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StaggeredListItem(
                index: 3,
                child: _buildServiceCard(
                  icon: Icons.history_rounded,
                  title: 'السجل',
                  description: 'نتائجك السابقة',
                  color: const Color(0xFF6B7280),
                  onTap: () {
                    AppFeedbackService.instance.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                title,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),

              // Description
              Text(
                description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ملفاتك لا يتم حفظها، يتم حفظ النتائج فقط في حسابك.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanUsageCard() {
    final plan = _currentPlan!;

    return InkWell(
      onTap: () {
        AppFeedbackService.instance.tap();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlansScreen()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Plan Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _getPlanColor(plan.planId).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getPlanIcon(plan.planId),
                    size: 14,
                    color: _getPlanColor(plan.planId),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    plan.planNameArabic,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _getPlanColor(plan.planId),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Usage Text
            Expanded(
              child: Text(
                plan.usageTextArabic,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),

            // Arrow
            Icon(
              Icons.chevron_left,
              size: 18,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPlanColor(String planId) {
    switch (planId) {
      case 'basic':
        return AppColors.primary;
      case 'pro':
        return AppColors.accent;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getPlanIcon(String planId) {
    switch (planId) {
      case 'basic':
        return Icons.star_rounded;
      case 'pro':
        return Icons.workspace_premium;
      default:
        return Icons.card_giftcard_rounded;
    }
  }
}
