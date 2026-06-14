import 'package:flutter/material.dart';
import '../models/selected_file_info.dart';
import '../models/summary_options.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/custom_button.dart';
import '../widgets/option_card.dart';
import 'result_screen.dart';

class SummaryOptionsScreen extends StatefulWidget {
  final SelectedFileInfo fileInfo;

  const SummaryOptionsScreen({
    super.key,
    required this.fileInfo,
  });

  @override
  State<SummaryOptionsScreen> createState() => _SummaryOptionsScreenState();
}

class _SummaryOptionsScreenState extends State<SummaryOptionsScreen> {
  int _selectedOutputType = 0;
  int _selectedLength = 0;

  final List<Map<String, dynamic>> _outputTypes = [
    {'icon': Icons.summarize, 'title': 'ملخص فقط'},
    {'icon': Icons.quiz, 'title': 'سؤال وجواب'},
    {'icon': Icons.auto_awesome, 'title': 'ملخص + سؤال وجواب'},
  ];

  final List<Map<String, dynamic>> _lengths = [
    {'icon': Icons.looks_one, 'title': 'صفحة واحدة'},
    {'icon': Icons.looks_5, 'title': '5 صفحات'},
    {'icon': Icons.looks, 'title': '10 صفحات'},
    {'icon': Icons.tune, 'title': 'مخصص'},
  ];

  void _navigateToResult() {
    final options = SummaryOptions(
      outputTypeIndex: _selectedOutputType,
      lengthIndex: _selectedLength,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          fileInfo: widget.fileInfo,
          options: options,
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'خيارات التلخيص',
            style: AppTextStyles.headlineSmall,
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // Show selected file info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
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
                            if (widget.fileInfo.fileSizeFormatted.isNotEmpty)
                              Text(
                                widget.fileInfo.fileSizeFormatted,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Extracted text preview
                if (widget.fileInfo.hasExtractedText) ...[
                  const SizedBox(height: 16),
                  _buildExtractedTextPreview(),
                ],
                const SizedBox(height: 24),
                Text(
                  'نوع المخرجات',
                  style: AppTextStyles.titleLarge,
                ),
                const SizedBox(height: 16),
                ...List.generate(_outputTypes.length, (index) {
                  final type = _outputTypes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionCard(
                      icon: type['icon'] as IconData,
                      title: type['title'] as String,
                      isSelected: _selectedOutputType == index,
                      onTap: () {
                        setState(() {
                          _selectedOutputType = index;
                        });
                      },
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Text(
                  'طول الملخص',
                  style: AppTextStyles.titleLarge,
                ),
                const SizedBox(height: 16),
                ...List.generate(_lengths.length, (index) {
                  final length = _lengths[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionCard(
                      icon: length['icon'] as IconData,
                      title: length['title'] as String,
                      isSelected: _selectedLength == index,
                      onTap: () {
                        setState(() {
                          _selectedLength = index;
                        });
                      },
                    ),
                  );
                }),
                const SizedBox(height: 32),
                CustomButton(
                  text: 'إنشاء النتيجة',
                  onPressed: _navigateToResult,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExtractedTextPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.text_snippet,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'معاينة النص المستخرج',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.fileInfo.extractedTextLengthFormatted,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Text(
                widget.fileInfo.extractedTextPreview,
                style: AppTextStyles.bodySmall.copyWith(
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
