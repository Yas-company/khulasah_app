import 'package:flutter/material.dart';
import '../models/document_history.dart';
import '../models/generated_result.dart';
import '../services/app_feedback_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_export_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';

/// Screen to display a saved history item's details.
class HistoryDetailScreen extends StatefulWidget {
  final DocumentHistory history;

  const HistoryDetailScreen({
    super.key,
    required this.history,
  });

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final PdfExportService _pdfExportService = PdfExportService.instance;
  final FirestoreService _firestoreService = FirestoreService.instance;
  bool _isExporting = false;
  bool _isDeleting = false;

  /// Show confirmation dialog for deleting the history item
  Future<bool> _showDeleteConfirmation() async {
    debugPrint('[HistoryDetail] Delete requested for: ${widget.history.id}');

    final confirmed = await showDialog<bool>(
      context: context,
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
                  color: AppColors.error.withOpacity(0.1),                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'حذف النتيجة؟',
                style: AppTextStyles.titleLarge,
              ),
            ],
          ),
          content: Text(
            'هل أنت متأكد أنك تريد حذف هذه النتيجة من السجل؟',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'إلغاء',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'حذف',
                style: AppTextStyles.labelLarge.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return confirmed ?? false;
  }

  /// Delete the history item
  Future<void> _deleteHistoryItem() async {
    if (_isDeleting || widget.history.id == null) return;

    final confirmed = await _showDeleteConfirmation();
    if (!confirmed) return;

    setState(() => _isDeleting = true);
    debugPrint('[HistoryDetail] Deleting document: ${widget.history.id}');

    final success = await _firestoreService.deleteDocumentHistory(widget.history.id!);

    if (!mounted) return;

    if (success) {
      debugPrint('[HistoryDetail] Delete success: ${widget.history.id}');
      await AppFeedbackService.instance.success();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف النتيجة من السجل'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate back and signal that the item was deleted
      Navigator.of(context).pop(true);
    } else {
      debugPrint('[HistoryDetail] Delete failed: ${widget.history.id}');
      await AppFeedbackService.instance.error();

      setState(() => _isDeleting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء حذف النتيجة'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Export history result to PDF
  Future<void> _exportPdf() async {
    if (_isExporting) return;

    // Check if there's content to export
    if (!widget.history.hasSummary && !widget.history.hasQuestionsAndAnswers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد نتائج محفوظة للتصدير'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    debugPrint('PDF export from history started');

    // Convert history to GeneratedResult
    List<QuestionAnswer>? qaList;
    if (widget.history.hasQuestionsAndAnswers) {
      qaList = widget.history.questionsAndAnswers!
          .map((qa) => QuestionAnswer(
                question: qa['question'] ?? '',
                answer: qa['answer'] ?? '',
              ))
          .toList();
    }

    // Determine result type based on available content
    GeneratedResultType resultType;
    if (widget.history.hasSummary && widget.history.hasQuestionsAndAnswers) {
      resultType = GeneratedResultType.summaryAndQuestions;
    } else if (widget.history.hasSummary) {
      resultType = GeneratedResultType.summaryOnly;
    } else {
      resultType = GeneratedResultType.questionsOnly;
    }

    final result = GeneratedResult(
      success: true,
      summary: widget.history.generatedSummary,
      questionsAndAnswers: qaList,
      resultType: resultType,
      generatedAt: widget.history.createdAt,
    );

    final success = await _pdfExportService.exportAndShare(
      fileName: widget.history.fileName,
      outputType: widget.history.outputType,
      summaryLength: widget.history.summaryLength,
      outputLanguage: widget.history.outputLanguage,
      result: result,
      pageRangeLabel: widget.history.pageRangeLabel,
    );

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (success) {
      debugPrint('PDF export from history success');
    } else {
      debugPrint('PDF export from history failed');
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'تفاصيل السجل',
            style: AppTextStyles.headlineSmall,
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
                      ),
                    )
                  : const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _isDeleting ? null : _deleteHistoryItem,
              tooltip: 'حذف النتيجة',
            ),
          ],
        ),
        body: SafeArea(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final hasContent =
        widget.history.hasSummary || widget.history.hasQuestionsAndAnswers;

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
                    color: Colors.black.withOpacity(0.04),
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
                      label: widget.history.fileName,
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
                          label: widget.history.outputTypeLabel,
                          color: AppColors.secondary,
                        ),
                        _buildInfoChip(
                          icon: Icons.format_size,
                          label: widget.history.summaryLengthLabel,
                          color: AppColors.accent,
                        ),
                        _buildInfoChip(
                          icon: Icons.language,
                          label: widget.history.outputLanguageLabel,
                          color: AppColors.primary,
                        ),
                        _buildInfoChip(
                          icon: Icons.calendar_today,
                          label: widget.history.formattedDateTime,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'حجم الملف: ${widget.history.fileSizeFormatted}',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'نطاق الصفحات: ${widget.history.pageRangeLabel}',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 20),
                    // Content sections
                    if (hasContent) ...[
                      // Summary section
                      if (widget.history.hasSummary) ...[
                        _buildSectionTitle(
                          icon: Icons.summarize,
                          title: 'الملخص',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.history.generatedSummary!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            height: 1.8,
                          ),
                        ),
                      ],
                      // Q&A section
                      if (widget.history.hasQuestionsAndAnswers) ...[
                        if (widget.history.hasSummary) ...[
                          const SizedBox(height: 24),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: 20),
                        ],
                        _buildSectionTitle(
                          icon: Icons.quiz,
                          title: 'الأسئلة والأجوبة',
                        ),
                        const SizedBox(height: 16),
                        ...widget.history.questionsAndAnswers!
                            .asMap()
                            .entries
                            .map(
                              (entry) => _buildQuestionAnswerCard(
                                index: entry.key + 1,
                                question: entry.value['question'] ?? '',
                                answer: entry.value['answer'] ?? '',
                              ),
                            ),
                      ],
                    ] else ...[
                      // No saved content
                      _buildNoContentState(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Export button (only show if content exists)
          if (hasContent)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isExporting ? null : _exportPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'تحميل PDF',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNoContentState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline,
              size: 32,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد نتائج محفوظة',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'تم حفظ معلومات الملف فقط دون النتائج',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],
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
    required String question,
    required String answer,
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
                  question,
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
              answer,
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
        color: color.withOpacity(0.1),
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
