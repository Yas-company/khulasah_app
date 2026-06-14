import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';

class FileUploadBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? selectedFileName;
  final VoidCallback? onTap;

  const FileUploadBox({
    super.key,
    this.icon = Icons.cloud_upload_outlined,
    required this.title,
    required this.subtitle,
    this.selectedFileName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = selectedFileName != null && selectedFileName!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: hasFile ? AppColors.primary.withValues(alpha: 0.05) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppColors.primary : AppColors.border,
            width: hasFile ? 2 : 1,
            style: hasFile ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: hasFile
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFile ? Icons.description : icon,
                color: hasFile ? AppColors.primary : AppColors.textSecondary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            if (hasFile) ...[
              Text(
                selectedFileName!,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'اضغط لتغيير الملف',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Text(
                title,
                style: AppTextStyles.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
