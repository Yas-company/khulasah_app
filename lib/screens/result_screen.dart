import 'package:flutter/material.dart';
import '../models/generated_result.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_export_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/custom_button.dart';
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

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  GeneratedResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _generateResult();
  }

  Future<void> _generateResult() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _backendService.generateResult(
        fileInfo: widget.fileInfo,
        options: widget.options,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _result = result;
          _isLoading = false;
        });

        // Auto-save to history for logged-in users
        _autoSaveToHistory();
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'حدث خطأ غير معروف';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال بالخدمة';
        _isLoading = false;
      });
    }
  }

  /// Auto-save to history for logged-in users (basic info only)
  Future<void> _autoSaveToHistory() async {
    if (_authService.isGuest) {
      debugPrint('Guest user - skipping auto history save');
      return;
    }

    final outputTypeMap = {0: 'summary', 1: 'qa', 2: 'both'};
    final lengthMap = {0: 'short', 1: 'medium', 2: 'long', 3: 'custom'};

    final docId = await _firestoreService.saveDocumentHistory(
      fileName: widget.fileInfo.fileName,
      fileSize: widget.fileInfo.fileSize ?? 0,
      extractedTextLength: widget.fileInfo.extractedText?.length ?? 0,
      outputType: outputTypeMap[widget.options.outputTypeIndex] ?? 'summary',
      summaryLength: lengthMap[widget.options.lengthIndex] ?? 'medium',
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
    final lengthMap = {0: 'short', 1: 'medium', 2: 'long', 3: 'custom'};

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
      summaryLength: lengthMap[widget.options.lengthIndex] ?? 'medium',
      generatedSummary: _result!.summary,
      questionsAndAnswers: qaList,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (docId != null) {
      debugPrint('Save result success: $docId');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ النتيجة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      debugPrint('Save result failed');
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
      debugPrint('[ResultScreen] Export blocked - already exporting or no result');
      return;
    }

    setState(() => _isExporting = true);
    debugPrint('[ResultScreen] Starting PDF export...');

    final outputTypeMap = {0: 'summaryOnly', 1: 'questionsOnly', 2: 'summaryAndQuestions'};
    final lengthMap = {0: 'short', 1: 'medium', 2: 'long', 3: 'medium'};

    final success = await _pdfExportService.exportAndShare(
      fileName: widget.fileInfo.fileName,
      outputType: outputTypeMap[widget.options.outputTypeIndex] ?? 'summaryOnly',
      summaryLength: lengthMap[widget.options.lengthIndex] ?? 'medium',
      result: _result!,
    );

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (success) {
      debugPrint('[ResultScreen] PDF export completed');
    } else {
      debugPrint('[ResultScreen] PDF export failed');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء تصدير الملف'),
          backgroundColor: AppColors.error,
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'النتيجة',
            style: AppTextStyles.headlineSmall,
          ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'جاري إنشاء النتيجة...',
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
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
          ],
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
            CustomButton(
              text: 'إعادة المحاولة',
              onPressed: _generateResult,
              width: 200,
            ),
            const SizedBox(height: 12),
            CustomButton(
              text: 'العودة للرئيسية',
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
              isOutlined: true,
              width: 200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    return Padding(
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
                      ],
                    ),
                    if (widget.fileInfo.fileSizeFormatted.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'حجم الملف: ${widget.fileInfo.fileSizeFormatted}',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
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
          CustomButton(
            text: 'العودة للرئيسية',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
            isOutlined: true,
          ),
          const SizedBox(height: 32),
        ],
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

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.primary,
          ),
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
                child: Text(
                  qa.question,
                  style: AppTextStyles.titleMedium,
                ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
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
