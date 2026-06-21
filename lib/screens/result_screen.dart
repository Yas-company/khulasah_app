import 'package:flutter/material.dart';
import '../models/generated_result.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import '../services/app_feedback_service.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/firestore_service.dart';
import '../services/large_document_processor.dart';
import '../services/pdf_export_service.dart';
import '../services/subscription_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/premium_button.dart';
import 'home_screen.dart';

class ResultScreen extends StatefulWidget {
  final SelectedFileInfo fileInfo;
  final SummaryOptions options;

  const ResultScreen({
    super.key,
    required this.fileInfo,
    required this.options,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final BackendService _backendService = BackendService();
  final FirestoreService _firestoreService = FirestoreService.instance;
  final AuthService _authService = AuthService.instance;
  final PdfExportService _pdfExportService = PdfExportService.instance;
  final SubscriptionService _subscriptionService = SubscriptionService.instance;
  late final LargeDocumentProcessor _largeDocumentProcessor;
  LargeDocumentCancellationToken? _cancellationToken;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  GeneratedResult? _result;
  String? _errorMessage;
  String _loadingMessage = 'جاري إنشاء النتيجة...';
  double? _loadingProgress;

  bool get _usesLargeDocumentFlow {
    final selectedPages =
        widget.fileInfo.actualToPage - widget.fileInfo.actualFromPage + 1;
    return widget.fileInfo.requiresLargeProcessing ||
        selectedPages > LargeDocumentProcessor.largeRangeThreshold;
  }

  @override
  void initState() {
    super.initState();
    _largeDocumentProcessor = LargeDocumentProcessor(
      backendService: _backendService,
    );
    _generateResult();
  }

  Future<void> _generateResult() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingMessage = 'جاري إنشاء النتيجة...';
      _loadingProgress = null;
    });

    try {
      final GeneratedResult result;
      if (_usesLargeDocumentFlow) {
        final filePath = widget.fileInfo.filePath;
        if (filePath == null || filePath.isEmpty) {
          result = GeneratedResult.error('مسار الملف غير متوفر');
        } else {
          _cancellationToken = LargeDocumentCancellationToken();
          result = await _largeDocumentProcessor.process(
            filePath: filePath,
            fileName: widget.fileInfo.fileName,
            totalPages: widget.fileInfo.totalPages,
            fromPage: widget.fileInfo.actualFromPage,
            toPage: widget.fileInfo.actualToPage,
            outputType: _outputTypeValue,
            summaryLength: widget.options.summaryLength,
            targetWords: widget.options.targetWords,
            targetPages: widget.options.targetPages,
            outputLanguage: widget.options.outputLanguageCode,
            cancellationToken: _cancellationToken!,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadingMessage = progress.message;
                  _loadingProgress = progress.fraction;
                });
              }
            },
          );
        }
      } else {
        result = await _backendService.generateResult(
          fileInfo: widget.fileInfo,
          options: widget.options,
          onProgress: (message) {
            if (mounted) {
              setState(() => _loadingMessage = message);
            }
          },
        );
      }

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _result = result;
          _isLoading = false;
        });

        // Trigger success feedback
        await AppFeedbackService.instance.success();

        // Increment usage counter for logged-in users
        _incrementUsage();

        // Auto-save to history for logged-in users
        _autoSaveToHistory();
      } else {
        await AppFeedbackService.instance.error();
        setState(() {
          _errorMessage = result.errorMessage ?? 'حدث خطأ غير معروف';
          _isLoading = false;
        });
      }
    } on LargeDocumentCancelledException {
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await AppFeedbackService.instance.error();
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال بالخدمة';
        _isLoading = false;
      });
    }
  }

  String get _outputTypeValue {
    const values = {
      0: 'summaryOnly',
      1: 'questionsOnly',
      2: 'summaryAndQuestions',
    };
    return values[widget.options.outputTypeIndex] ?? 'summaryOnly';
  }

  void _cancelLargeDocumentProcessing() {
    _cancellationToken?.cancel();
    setState(() {
      _loadingMessage = 'جاري الإلغاء...';
    });
  }

  /// Increment usage counter after successful generation
  Future<void> _incrementUsage() async {
    final uid = _authService.userId;
    if (uid == null) {
      debugPrint('[ResultScreen] Guest user - skipping usage increment');
      return;
    }

    try {
      await _subscriptionService.incrementUsageAfterSuccess(uid);
      debugPrint('[ResultScreen] Usage incremented successfully');
    } catch (e) {
      debugPrint('[ResultScreen] Failed to increment usage: $e');
      // Don't show error to user - usage tracking is not critical
    }
  }

  /// Auto-save to history for logged-in users (basic info only)
  Future<void> _autoSaveToHistory() async {
    if (_authService.isGuest) {
      debugPrint('Guest user - skipping auto history save');
      return;
    }

    final outputTypeMap = {0: 'summary', 1: 'qa', 2: 'both'};
    final docId = await _firestoreService.saveDocumentHistory(
      fileName: widget.fileInfo.fileName,
      fileSize: widget.fileInfo.fileSize ?? 0,
      extractedTextLength: widget.fileInfo.extractedText?.length ?? 0,
      outputType: outputTypeMap[widget.options.outputTypeIndex] ?? 'summary',
      summaryLength: widget.options.summaryLength,
      outputLanguage: widget.options.outputLanguageCode,
      totalPages: widget.fileInfo.totalPages,
      fromPage: widget.fileInfo.actualFromPage,
      toPage: widget.fileInfo.actualToPage,
      pageRangeLabel: widget.fileInfo.pageRangeLabel,
    );

    if (docId != null) {
      debugPrint('History saved to Firestore: $docId');
    }
  }

  /// Save full result to Firestore
  Future<void> _saveResult() async {
    if (_isSaving || _result == null) return;

    // Check if guest
    if (_authService.isGuest) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تسجيل الدخول لحفظ النتائج'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    debugPrint('Save result started');

    final outputTypeMap = {0: 'summary', 1: 'qa', 2: 'both'};
    // Convert Q&A to list of maps
    List<Map<String, String>>? qaList;
    if (_result!.hasQuestions) {
      qaList = _result!.questionsAndAnswers!
          .map((qa) => {'question': qa.question, 'answer': qa.answer})
          .toList();
    }

    final docId = await _firestoreService.saveFullResult(
      fileName: widget.fileInfo.fileName,
      fileSize: widget.fileInfo.fileSize ?? 0,
      extractedTextLength: widget.fileInfo.extractedText?.length ?? 0,
      outputType: outputTypeMap[widget.options.outputTypeIndex] ?? 'summary',
      summaryLength: widget.options.summaryLength,
      outputLanguage: widget.options.outputLanguageCode,
      generatedSummary: _result!.summary,
      questionsAndAnswers: qaList,
      totalPages: widget.fileInfo.totalPages,
      fromPage: widget.fileInfo.actualFromPage,
      toPage: widget.fileInfo.actualToPage,
      pageRangeLabel: widget.fileInfo.pageRangeLabel,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (docId != null) {
      debugPrint('Save result success: $docId');
      await AppFeedbackService.instance.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ النتيجة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      debugPrint('Save result failed');
      await AppFeedbackService.instance.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء حفظ النتيجة'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Export result to PDF and share
  Future<void> _exportPdf() async {
    // Prevent double-click
    if (_isExporting || _result == null) {
      debugPrint(
        '[ResultScreen] Export blocked - already exporting or no result',
      );
      return;
    }

    setState(() => _isExporting = true);
    debugPrint('[ResultScreen] Starting PDF export...');

    final outputTypeMap = {
      0: 'summaryOnly',
      1: 'questionsOnly',
      2: 'summaryAndQuestions',
    };
    final lengthMap = {0: 'short', 1: 'medium', 2: 'long', 3: 'medium'};

    final success = await _pdfExportService.exportAndShare(
      context: context,
      fileName: widget.fileInfo.fileName,
      outputType:
      outputTypeMap[widget.options.outputTypeIndex] ?? 'summaryOnly',
      summaryLength: lengthMap[widget.options.lengthIndex] ?? 'medium',
      outputLanguage: widget.options.outputLanguageCode,
      result: _result!,
      pageRangeLabel: widget.fileInfo.pageRangeLabel,
    );

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (success) {
      debugPrint('[ResultScreen] PDF export completed');
      await AppFeedbackService.instance.success();
    } else {
      debugPrint('[ResultScreen] PDF export failed');
      await AppFeedbackService.instance.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pdfExportService.getErrorMessage()),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
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
            onPressed: () {
              if (_isLoading && _usesLargeDocumentFlow) {
                _cancelLargeDocumentProcessing();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text('النتيجة', style: AppTextStyles.headlineSmall),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _isLoading
              ? _buildLoadingState()
              : _errorMessage != null
              ? _buildErrorState()
              : _buildResultContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FadeSlideTransition(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedLoadingIndicator(
                message: _loadingMessage,
                color: AppColors.primary,
                size: 56,
              ),
              if (_loadingProgress != null) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: _loadingProgress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.primary,
                  backgroundColor: AppColors.border,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_loadingProgress! * 100).round()}%',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                widget.fileInfo.fileName,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.options.outputTypeLabel,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              if (_usesLargeDocumentFlow) ...[
                const SizedBox(height: 12),
                Text(
                  'يرجى إبقاء التطبيق مفتوحًا أثناء معالجة الملفات الكبيرة.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _cancelLargeDocumentProcessing,
                  child: const Text('إلغاء'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'حدث خطأ',
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PremiumButton(
              text: 'إعادة المحاولة',
              onPressed: _generateResult,
              width: 200,
              icon: Icons.refresh_rounded,
            ),
            const SizedBox(height: 12),
            PremiumButton(
              text: 'العودة للرئيسية',
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              isOutlined: true,
              width: 200,
              icon: Icons.home_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    return FadeSlideTransition(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File info chip
                      _buildInfoChip(
                        icon: Icons.description,
                        label: widget.fileInfo.fileName,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      // Options row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(
                            icon: Icons.category,
                            label: widget.options.outputTypeLabel,
                            color: AppColors.secondary,
                          ),
                          _buildInfoChip(
                            icon: Icons.format_size,
                            label: widget.options.lengthLabel,
                            color: AppColors.accent,
                          ),
                          _buildInfoChip(
                            icon: Icons.language,
                            label: widget.options.outputLanguageLabel,
                            color: AppColors.primary,
                          ),
                          _buildInfoChip(
                            icon: Icons.auto_stories,
                            label: widget.fileInfo.pageRangeLabelShort,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      if (widget.fileInfo.fileSizeFormatted.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'حجم الملف: ${widget.fileInfo.fileSizeFormatted}',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                      // Page range info
                      const SizedBox(height: 4),
                      Text(
                        'نطاق الصفحات: ${widget.fileInfo.pageRangeLabel}',
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 20),
                      // Generated result sections
                      if (_result != null) ...[
                        // Summary section
                        if (_result!.hasSummary) ...[
                          _buildSectionTitle(
                            icon: Icons.summarize,
                            title: 'الملخص',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _result!.summary!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              height: 1.8,
                            ),
                          ),
                        ],
                        // Q&A section
                        if (_result!.hasQuestions) ...[
                          if (_result!.hasSummary) ...[
                            const SizedBox(height: 24),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 20),
                          ],
                          _buildSectionTitle(
                            icon: Icons.quiz,
                            title: 'الأسئلة والأجوبة',
                          ),
                          const SizedBox(height: 16),
                          ..._result!.questionsAndAnswers!.asMap().entries.map(
                            (entry) => _buildQuestionAnswerCard(
                              index: entry.key + 1,
                              qa: entry.value,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    text: _isExporting ? 'جاري التصدير...' : 'تحميل PDF',
                    icon: _isExporting ? null : Icons.download,
                    isLoading: _isExporting,
                    onPressed: (_isExporting || _isSaving) ? null : _exportPdf,
                    isOutlined: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    text: _isSaving ? 'جاري الحفظ...' : 'حفظ النتيجة',
                    icon: _isSaving ? null : Icons.save,
                    isLoading: _isSaving,
                    onPressed: (_isSaving || _isExporting) ? null : _saveResult,
                    isOutlined: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PremiumButton(
              text: 'العودة للرئيسية',
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              isOutlined: true,
              icon: Icons.home_rounded,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    IconData? icon,
    required bool isLoading,
    required VoidCallback? onPressed,
    required bool isOutlined,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.transparent : AppColors.primary,
          foregroundColor: isOutlined ? AppColors.primary : Colors.white,
          elevation: isOutlined ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isOutlined
                ? const BorderSide(color: AppColors.primary)
                : BorderSide.none,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    text,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isOutlined ? AppColors.primary : Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionTitle({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.titleLarge.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildQuestionAnswerCard({
    required int index,
    required QuestionAnswer qa,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(qa.question, style: AppTextStyles.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              qa.answer,
              style: AppTextStyles.bodyMedium.copyWith(
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
