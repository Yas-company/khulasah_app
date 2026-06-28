import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/selected_file_info.dart';
import '../services/pdf_text_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../widgets/custom_button.dart';
import '../widgets/file_upload_box.dart';
import 'summary_options_screen.dart';

class UploadPdfScreen extends StatefulWidget {
  final int? initialOutputType;

  const UploadPdfScreen({super.key, this.initialOutputType});

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  SelectedFileInfo? _selectedFile;
  bool _isLoading = false;
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

      final stableFilePath = file.path == null
          ? null
          : await _copyPdfToAppDocuments(
              sourcePath: file.path!,
              fileName: file.name,
            );

      // Get page count for the PDF (no text extraction yet)
      int totalPages = 0;
      if (stableFilePath != null) {
        final pageCountResult = await _pdfTextService.getPageCount(stableFilePath);
        if (pageCountResult.success) {
          totalPages = pageCountResult.pageCount;
          debugPrint('[UploadPdf] totalPages: $totalPages');
        }
      }

      setState(() {
        _selectedFile = SelectedFileInfo(
          fileName: file.name,
          filePath: stableFilePath,
          fileSize: file.size,
          totalPages: totalPages,
          selectedToPage: totalPages, // Default to all pages
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

  Future<String> _copyPdfToAppDocuments({
    required String sourcePath,
    required String fileName,
  }) async {
    final sourceFile = File(sourcePath);
    final docsDir = await getApplicationDocumentsDirectory();
    final uploadsDir = Directory('${docsDir.path}/uploaded_pdfs');
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }

    final safeName = _safePdfFileName(fileName);
    final savedPath =
        '${uploadsDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final savedFile = await sourceFile.copy(savedPath);
    debugPrint('[UploadPdf] stable file path: ${savedFile.path}');
    return savedFile.path;
  }

  String _safePdfFileName(String fileName) {
    final normalized = fileName.trim().isEmpty ? 'document.pdf' : fileName;
    final safeName = normalized.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return safeName.toLowerCase().endsWith('.pdf') ? safeName : '$safeName.pdf';
  }

  /// Navigate to options screen without extracting text.
  /// Text extraction will happen in SummaryOptionsScreen when user selects page range.
  void _navigateToOptions() {
    if (_selectedFile == null) return;

    debugPrint('[UploadPdf] Navigating to options without full extraction');
    debugPrint('[UploadPdf] fileName: ${_selectedFile!.fileName}');
    debugPrint('[UploadPdf] totalPages: ${_selectedFile!.totalPages}');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SummaryOptionsScreen(
          fileInfo: _selectedFile!,
          initialOutputType: widget.initialOutputType,
        ),
      ),
    );
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
            onPressed: () => Navigator.of(context).pop(),
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
                  child: FileUploadBox(
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
                    text: 'متابعة',
                    onPressed: _navigateToOptions,
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
