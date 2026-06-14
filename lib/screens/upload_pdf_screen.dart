import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/selected_file_info.dart';
import '../services/pdf_text_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/custom_button.dart';
import '../widgets/file_upload_box.dart';
import 'summary_options_screen.dart';

class UploadPdfScreen extends StatefulWidget {
  const UploadPdfScreen({super.key});

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  SelectedFileInfo? _selectedFile;
  bool _isLoading = false;
  bool _isExtracting = false;
  final PdfTextService _pdfTextService = PdfTextService();

  Future<void> _selectFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final file = result.files.first;

      if (file.extension?.toLowerCase() != 'pdf') {
        if (mounted) {
          _showErrorSnackBar('يرجى اختيار ملف PDF فقط');
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _selectedFile = SelectedFileInfo(
          fileName: file.name,
          filePath: file.path,
          fileSize: file.size,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showErrorSnackBar('حدث خطأ أثناء اختيار الملف');
      }
    }
  }

  Future<void> _extractTextAndNavigate() async {
    if (_selectedFile == null) return;

    setState(() {
      _isExtracting = true;
    });

    try {
      final result = await _pdfTextService.extractText(_selectedFile!.filePath);

      if (!mounted) return;

      if (result.success) {
        final updatedFile = _selectedFile!.copyWith(
          extractedText: result.text,
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SummaryOptionsScreen(fileInfo: updatedFile),
          ),
        );
      } else {
        _showErrorSnackBar(result.errorMessage ?? 'حدث خطأ غير معروف');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('حدث خطأ أثناء استخراج النص');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _selectedFile != null;

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
          title: Text(
            'رفع ملف PDF',
            style: AppTextStyles.headlineSmall,
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Expanded(
                  child: _isExtracting
                      ? _buildExtractingState()
                      : FileUploadBox(
                          icon: Icons.cloud_upload_outlined,
                          title: 'اسحب ملفك هنا أو اختر ملف PDF',
                          subtitle: _selectedFile != null
                              ? _selectedFile!.fileSizeFormatted
                              : 'يدعم ملفات PDF فقط',
                          selectedFileName: _selectedFile?.fileName,
                          onTap: _isLoading ? null : _selectFile,
                        ),
                ),
                const SizedBox(height: 24),
                if (!hasFile)
                  CustomButton(
                    text: 'اختيار ملف PDF',
                    onPressed: _selectFile,
                    isLoading: _isLoading,
                  )
                else
                  CustomButton(
                    text: _isExtracting ? 'جاري استخراج النص...' : 'متابعة',
                    onPressed: _isExtracting ? null : _extractTextAndNavigate,
                    isLoading: _isExtracting,
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExtractingState() {
    return Center(
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
            'جاري استخراج النص من الملف...',
            style: AppTextStyles.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFile?.fileName ?? '',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
