import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import '../models/user_plan.dart';
import '../services/app_feedback_service.dart';
import '../services/auth_service.dart';
import '../services/large_document_processor.dart';
import '../services/pdf_text_service.dart';
import '../services/subscription_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/option_card.dart';
import '../widgets/paywall_dialog.dart';
import '../widgets/premium_button.dart';
import 'result_screen.dart';

class SummaryOptionsScreen extends StatefulWidget {
  final SelectedFileInfo fileInfo;

  const SummaryOptionsScreen({super.key, required this.fileInfo});

  @override
  State<SummaryOptionsScreen> createState() => _SummaryOptionsScreenState();
}

class _SummaryOptionsScreenState extends State<SummaryOptionsScreen>
    with SingleTickerProviderStateMixin {
  // Large text-based PDFs are processed in stages by BackendService.
  static const int _largePdfPageThreshold =
      LargeDocumentProcessor.largeRangeThreshold;

  int _selectedOutputType = 0;
  int _selectedLength = 0;
  int _selectedLanguage = 0;
  bool _isProcessing = true;
  bool _isExtracting = false;
  String _extractionStatusMessage = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Page range state
  int _selectedPageRangeOption = 0; // 0 = all pages, 1 = custom range
  late TextEditingController _fromPageController;
  late TextEditingController _toPageController;
  late TextEditingController _customTargetPagesController;
  late TextEditingController _customTargetWordsController;
  String? _pageRangeError;
  String? _customLengthError;

  /// Whether this PDF is considered large (> threshold pages)
  bool get _isLargePdf => widget.fileInfo.totalPages > _largePdfPageThreshold;

  // Subscription state
  UserPlan? _currentPlan;
  String? _planLimitWarning;

  final PdfTextService _pdfTextService = PdfTextService();
  final SubscriptionService _subscriptionService = SubscriptionService.instance;

  final List<Map<String, dynamic>> _outputTypes = [
    {'icon': Icons.summarize, 'title': 'ملخص فقط'},
    {'icon': Icons.quiz, 'title': 'سؤال وجواب'},
    {'icon': Icons.auto_awesome, 'title': 'ملخص + سؤال وجواب'},
  ];

  final List<Map<String, dynamic>> _lengths = [
    {'icon': Icons.looks_one, 'title': 'صفحة واحدة', 'subtitle': 'ملخص مختصر'},
    {'icon': Icons.looks_5, 'title': '5 صفحات', 'subtitle': 'ملخص مفصل'},
    {'icon': Icons.looks, 'title': '10 صفحات', 'subtitle': 'ملخص عميق وموسع'},
    {'icon': Icons.tune, 'title': 'مخصص', 'subtitle': 'حدد الطول المناسب لك'},
  ];

  final List<Map<String, dynamic>> _languages = [
    {'icon': Icons.language, 'title': 'العربية'},
    {'icon': Icons.translate, 'title': 'English'},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // Initialize page range controllers
    final totalPages = widget.fileInfo.totalPages;
    _fromPageController = TextEditingController(text: '1');

    _toPageController = TextEditingController(
      text: totalPages > 0 ? '$totalPages' : '1',
    );
    _customTargetPagesController = TextEditingController(text: '2');
    _customTargetWordsController = TextEditingController(text: '1000');

    // Log info (internal only)
    _logInfo();

    // Load current subscription plan
    _loadCurrentPlan();

    // Brief processing delay for smooth UX transition
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        _animationController.forward();
      }
    });
  }

  void _logInfo() {
    debugPrint('[SummaryOptions] totalPages: ${widget.fileInfo.totalPages}');
    debugPrint('[SummaryOptions] fileName: ${widget.fileInfo.fileName}');
  }

  Future<void> _loadCurrentPlan() async {
    final uid = AuthService.instance.userId;
    if (uid != null) {
      final plan = await _subscriptionService.getCurrentPlan(uid);
      if (mounted) {
        setState(() {
          _currentPlan = plan;
        });
        _checkPlanLimits();
      }
    }
  }

  void _checkPlanLimits() {
    // Design-only mode: never show plan limit warnings
    if (designOnlyMode) {
      setState(() {
        _planLimitWarning = null;
      });
      return;
    }

    if (_currentPlan == null) return;

    final selectedPageCount = _getSelectedPageCount();
    final maxPages = _currentPlan!.maxPagesPerRequest;

    debugPrint('[SummaryOptions] Plan: ${_currentPlan!.planId}');
    debugPrint(
      '[SummaryOptions] Selected pages: $selectedPageCount, Max allowed: $maxPages',
    );

    if (selectedPageCount > maxPages) {
      setState(() {
        _planLimitWarning = 'خطتك الحالية تسمح بتلخيص $maxPages صفحات كحد أقصى';
      });
    } else {
      setState(() {
        _planLimitWarning = null;
      });
    }
  }

  int _getSelectedPageCount() {
    final totalPages = widget.fileInfo.totalPages;
    if (_selectedPageRangeOption == 0) {
      // All pages
      return totalPages > 0 ? totalPages : 1;
    } else {
      // Custom range
      final from = int.tryParse(_fromPageController.text) ?? 1;
      final to = int.tryParse(_toPageController.text) ?? totalPages;
      return (to - from + 1).clamp(1, totalPages);
    }
  }

  String _getOutputTypeString() {
    switch (_selectedOutputType) {
      case 0:
        return 'summaryOnly';
      case 1:
        return 'questionsOnly';
      case 2:
        return 'summaryAndQuestions';
      default:
        return 'summaryOnly';
    }
  }

  String _getSummaryLengthString() {
    return _buildSummaryOptions().summaryLength;
  }

  SummaryOptions _buildSummaryOptions() {
    return SummaryOptions(
      outputTypeIndex: _selectedOutputType,
      lengthIndex: _selectedLength,
      outputLanguageIndex: _selectedLanguage,
      customTargetWords: _selectedLength == 3
          ? int.tryParse(_customTargetWordsController.text)
          : null,
      customTargetPages: _selectedLength == 3
          ? int.tryParse(_customTargetPagesController.text)
          : null,
    );
  }

  bool _validateCustomLength() {
    if (_selectedLength != 3) {
      _customLengthError = null;
      return true;
    }

    final pages = int.tryParse(_customTargetPagesController.text);
    final words = int.tryParse(_customTargetWordsController.text);
    if (pages == null || pages < 1 || pages > 20) {
      _customLengthError = 'عدد الصفحات يجب أن يكون بين 1 و20';
      return false;
    }
    if (words == null || words < 300 || words > 10000) {
      _customLengthError = 'عدد الكلمات يجب أن يكون بين 300 و10000';
      return false;
    }

    _customLengthError = null;
    return true;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fromPageController.dispose();
    _toPageController.dispose();
    _customTargetPagesController.dispose();
    _customTargetWordsController.dispose();
    super.dispose();
  }

  /// Validate page range inputs
  bool _validatePageRange() {
    if (_selectedPageRangeOption == 0) {
      _pageRangeError = null;
      return true;
    }

    final totalPages = widget.fileInfo.totalPages;
    if (totalPages == 0) {
      _pageRangeError = 'لم يتم تحديد عدد صفحات الملف';
      return false;
    }

    final fromPage = int.tryParse(_fromPageController.text);
    final toPage = int.tryParse(_toPageController.text);

    if (fromPage == null || toPage == null) {
      _pageRangeError = 'يرجى إدخال أرقام صحيحة';
      return false;
    }

    if (fromPage < 1) {
      _pageRangeError = 'رقم الصفحة يجب أن يكون 1 على الأقل';
      return false;
    }

    if (toPage > totalPages) {
      _pageRangeError = 'لا يمكن أن يتجاوز رقم الصفحة $totalPages';
      return false;
    }

    if (fromPage > toPage) {
      _pageRangeError = 'صفحة البداية يجب أن تكون أقل من صفحة النهاية';
      return false;
    }

    _pageRangeError = null;
    return true;
  }

  Future<void> _extractAndNavigate() async {
    // Validate page range first
    setState(() {
      _validatePageRange();
      _validateCustomLength();
    });

    if (_pageRangeError != null || _customLengthError != null) {
      return;
    }

    final summaryOptions = _buildSummaryOptions();
    debugPrint(
      '[SummaryOptions] summaryLength: ${summaryOptions.summaryLength}',
    );
    debugPrint('[SummaryOptions] targetWords: ${summaryOptions.targetWords}');

    // Check subscription limits
    final uid = AuthService.instance.userId;
    if (uid != null) {
      final selectedPageCount = _getSelectedPageCount();
      final outputType = _getOutputTypeString();
      final summaryLength = _getSummaryLengthString();

      debugPrint(
        '[SummaryOptions] Checking limits - pages: $selectedPageCount, output: $outputType, length: $summaryLength',
      );

      final checkResult = await _subscriptionService.checkCanGenerate(
        uid: uid,
        selectedPageCount: selectedPageCount,
        outputType: outputType,
        summaryLength: summaryLength,
      );

      if (!checkResult.allowed) {
        debugPrint('[SummaryOptions] BLOCKED: ${checkResult.blockedReason}');
        if (mounted) {
          await showPaywallDialog(
            context: context,
            customTitle: 'لقد وصلت إلى الحد المجاني',
            customSubtitle: checkResult.blockedReasonArabic,
          );
        }
        return;
      }
    }

    setState(() {
      _isExtracting = true;
      _extractionStatusMessage = 'جاري قراءة محتوى الصفحات...';
    });

    try {
      // Determine page range
      final useCustomRange = _selectedPageRangeOption == 1;
      final fromPage = useCustomRange ? int.parse(_fromPageController.text) : 1;
      final toPage = useCustomRange
          ? int.parse(_toPageController.text)
          : widget.fileInfo.totalPages;

      final pageCount = toPage - fromPage + 1;
      debugPrint(
        '[SummaryOptions] Extracting pages: $fromPage-$toPage ($pageCount pages)',
      );
      debugPrint('[SummaryOptions] isLargePdf: $_isLargePdf');

      if (pageCount > LargeDocumentProcessor.largeRangeThreshold) {
        _navigateToResult(
          fromPage: fromPage,
          toPage: toPage,
          useCustomRange: useCustomRange,
        );
        return;
      }

      // Extract text with automatic internal fallback for scanned PDFs
      final extendedResult = await _pdfTextService.extractTextWithOcrFallback(
        filePath: widget.fileInfo.filePath,
        fromPage: fromPage,
        toPage: toPage,
        onNormalExtractionStart: () {
          if (mounted) {
            setState(() {
              _extractionStatusMessage = 'جاري قراءة محتوى الصفحات...';
            });
          }
        },
        onOcrFallbackStart: () {
          if (mounted) {
            setState(() {
              _extractionStatusMessage =
                  'يتم الآن معالجة الصفحات، قد يستغرق ذلك وقتًا أطول قليلًا.';
            });
          }
        },
        onPageProcessed: (current, total) {
          debugPrint('[SummaryOptions] Processing page $current/$total');
        },
      );

      if (!mounted) return;

      // Handle different extraction statuses
      switch (extendedResult.status) {
        case ExtractionStatus.success:
          // Text was extracted successfully (either direct or via internal processing)
          final result = extendedResult.extractionResult;
          debugPrint(
            '[SummaryOptions] Extraction success: ${result.text?.length ?? 0} chars',
          );
          debugPrint(
            '[SummaryOptions] Content source: ${result.contentSource}',
          );

          // Update file info with extraction result
          final updatedFile = widget.fileInfo.copyWith(
            extractedText: result.text,
            textQuality: result.quality,
            readableRatio: result.readableRatio,
            errorMessage: result.errorMessage,
            useCustomPageRange: useCustomRange,
            selectedFromPage: fromPage,
            selectedToPage: toPage,
          );

          final options = _buildSummaryOptions();

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ResultScreen(fileInfo: updatedFile, options: options),
            ),
          );
          break;

        case ExtractionStatus.tooManyPagesForOcr:
          debugPrint('[SummaryOptions] Switching to staged processing');
          _navigateToResult(
            fromPage: fromPage,
            toPage: toPage,
            useCustomRange: useCustomRange,
            requiresLargeProcessing: true,
          );
          break;

        case ExtractionStatus.failed:
          // Both normal extraction and internal processing failed
          debugPrint('[SummaryOptions] Extraction failed completely');
          await _showExtractionFailedDialog();
          break;

        case ExtractionStatus.fileError:
          // File error occurred
          debugPrint(
            '[SummaryOptions] File error: ${extendedResult.statusMessage}',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  extendedResult.statusMessage ?? 'حدث خطأ أثناء قراءة الملف',
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
          break;
      }
    } catch (e) {
      debugPrint('[SummaryOptions] Extraction error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء قراءة الملف'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _extractionStatusMessage = '';
        });
      }
    }
  }

  void _navigateToResult({
    required int fromPage,
    required int toPage,
    required bool useCustomRange,
    bool requiresLargeProcessing = false,
  }) {
    if (!mounted) return;

    final updatedFile = widget.fileInfo.copyWith(
      useCustomPageRange: useCustomRange,
      selectedFromPage: fromPage,
      selectedToPage: toPage,
      requiresLargeProcessing: requiresLargeProcessing,
    );
    final options = _buildSummaryOptions();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(fileInfo: updatedFile, options: options),
      ),
    );
  }

  /// Show dialog when both normal extraction and internal processing fail
  Future<void> _showExtractionFailedDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تعذر قراءة الملف',
                  style: AppTextStyles.titleLarge,
                ),
              ),
            ],
          ),
          content: Text(
            'لم نتمكن من قراءة نص واضح من الصفحات المحددة. جرّب اختيار صفحات أخرى أو استخدم ملف PDF أوضح.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'حسنًا',
                style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
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
            onPressed: _isExtracting ? null : () => Navigator.of(context).pop(),
          ),
          title: Text('خيارات التلخيص', style: AppTextStyles.headlineSmall),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // File info card
                _buildFileInfoCard(),
                const SizedBox(height: 16),
                // Status card (processing or ready)
                _buildStatusCard(),
                // Options sections
                const SizedBox(height: 24),

                // Page Range Section
                _buildPageRangeSection(),

                // Plan limit warning
                if (_planLimitWarning != null) ...[
                  const SizedBox(height: 12),
                  _buildPlanLimitWarning(),
                ],
                const SizedBox(height: 24),

                // Output Language Section
                Text('لغة النتيجة', style: AppTextStyles.titleLarge),
                const SizedBox(height: 16),
                ...List.generate(_languages.length, (index) {
                  final lang = _languages[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionCard(
                      icon: lang['icon'] as IconData,
                      title: lang['title'] as String,
                      isSelected: _selectedLanguage == index,
                      onTap: _isExtracting
                          ? null
                          : () {
                              AppFeedbackService.instance.selection();
                              setState(() {
                                _selectedLanguage = index;
                              });
                            },
                    ),
                  );
                }),
                const SizedBox(height: 24),

                // Output Type Section
                Text('نوع المخرجات', style: AppTextStyles.titleLarge),
                const SizedBox(height: 16),
                ...List.generate(_outputTypes.length, (index) {
                  final type = _outputTypes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionCard(
                      icon: type['icon'] as IconData,
                      title: type['title'] as String,
                      isSelected: _selectedOutputType == index,
                      onTap: _isExtracting
                          ? null
                          : () {
                              AppFeedbackService.instance.selection();
                              setState(() {
                                _selectedOutputType = index;
                              });
                            },
                    ),
                  );
                }),
                const SizedBox(height: 24),

                // Length Section
                Text('طول الملخص', style: AppTextStyles.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'الطول تقديري ويعتمد على حجم الملف والمحتوى.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(_lengths.length, (index) {
                  final length = _lengths[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionCard(
                      icon: length['icon'] as IconData,
                      title: length['title'] as String,
                      subtitle: length['subtitle'] as String?,
                      isSelected: _selectedLength == index,
                      onTap: _isExtracting
                          ? null
                          : () {
                              AppFeedbackService.instance.selection();
                              setState(() {
                                _selectedLength = index;
                                _customLengthError = null;
                              });
                            },
                    ),
                  );
                }),
                if (_selectedLength == 3) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCustomLengthField(
                          controller: _customTargetPagesController,
                          label: 'عدد الصفحات',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCustomLengthField(
                          controller: _customTargetWordsController,
                          label: 'عدد الكلمات',
                        ),
                      ),
                    ],
                  ),
                  if (_customLengthError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _customLengthError!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 32),

                // Extraction status message
                if (_isExtracting && _extractionStatusMessage.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _extractionStatusMessage,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Generate button
                PremiumButton(
                  text: 'إنشاء النتيجة',
                  onPressed: _extractAndNavigate,
                  isLoading: _isExtracting,
                  icon: Icons.auto_awesome_rounded,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageRangeSection() {
    final totalPages = widget.fileInfo.totalPages;
    final hasTotalPages = totalPages > 0;
    final isLargePdf = _isLargePdf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('نطاق الصفحات', style: AppTextStyles.titleLarge),
            if (hasTotalPages) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalPages صفحة',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Large PDF warning
        if (isLargePdf) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'هذا الملف كبير وقد تستغرق معالجته وقتًا أطول.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'قد تستغرق النتيجة وقتًا أطول حسب عدد الصفحات.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يرجى إبقاء التطبيق مفتوحًا أثناء معالجة الملفات الكبيرة.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // All pages option
        OptionCard(
          icon: Icons.select_all,
          title: 'كل الصفحات',
          subtitle: hasTotalPages ? 'من 1 إلى $totalPages' : null,
          isSelected: _selectedPageRangeOption == 0,
          onTap: _isExtracting
              ? null
              : () {
                  AppFeedbackService.instance.selection();
                  setState(() {
                    _selectedPageRangeOption = 0;
                    _pageRangeError = null;
                  });
                  _checkPlanLimits();
                },
        ),
        const SizedBox(height: 12),

        // Custom range option
        OptionCard(
          icon: Icons.straighten,
          title: 'صفحات محددة',
          subtitle: 'اختر نطاق معين من الصفحات',
          isSelected: _selectedPageRangeOption == 1,
          onTap: _isExtracting
              ? null
              : () {
                  AppFeedbackService.instance.selection();
                  setState(() {
                    _selectedPageRangeOption = 1;
                  });
                  _checkPlanLimits();
                },
        ),

        // Custom range inputs (only shown when custom range is selected)
        if (_selectedPageRangeOption == 1) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildPageInputField(
                        controller: _fromPageController,
                        label: 'من صفحة',
                        hint: '1',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildPageInputField(
                        controller: _toPageController,
                        label: 'إلى صفحة',
                        hint: hasTotalPages ? '$totalPages' : '10',
                      ),
                    ),
                  ],
                ),
                if (_pageRangeError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _pageRangeError!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPageInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          enabled: !_isExtracting,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
          onChanged: (_) {
            // Clear error when user types
            if (_pageRangeError != null) {
              setState(() {
                _pageRangeError = null;
              });
            }
            // Check plan limits after input change
            _checkPlanLimits();
          },
        ),
      ],
    );
  }

  Widget _buildCustomLengthField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_isExtracting,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (_) {
        if (_customLengthError != null) {
          setState(() => _customLengthError = null);
        }
      },
    );
  }

  Widget _buildFileInfoCard() {
    final totalPages = widget.fileInfo.totalPages;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.description,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fileInfo.fileName,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (widget.fileInfo.fileSizeFormatted.isNotEmpty)
                      Text(
                        widget.fileInfo.fileSizeFormatted,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (widget.fileInfo.fileSizeFormatted.isNotEmpty &&
                        totalPages > 0)
                      Text(
                        ' • ',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (totalPages > 0)
                      Text(
                        '$totalPages صفحة',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_isProcessing) {
      return _buildProcessingCard();
    }

    return FadeTransition(opacity: _fadeAnimation, child: _buildReadyCard());
  }

  Widget _buildProcessingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'جاري تجهيز الملف...',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تم تجهيز الملف',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'الملف جاهز للتلخيص',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'اختر نطاق الصفحات والخيارات المناسبة ثم اضغط على إنشاء النتيجة.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanLimitWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _planLimitWarning!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
