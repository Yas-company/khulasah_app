import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/generated_result.dart';

/// Error codes for PDF export
enum PdfExportError {
  none,
  fontLoadFailed,
  pdfBuildFailed,
  pdfSaveFailed,
  pdfShareFailed,
}

/// Service for exporting results to PDF and sharing.
///
/// Creates Arabic-friendly PDF documents with:
/// - Arabic font support (Amiri - static TTF)
/// - RTL text direction
/// - App branding
/// - File information
/// - Generated summary
/// - Questions and answers
class PdfExportService {
  static PdfExportService? _instance;

  // Cached fonts - using Amiri (static TTF fonts)
  pw.Font? _arabicFont;
  pw.Font? _arabicBoldFont;
  bool _fontsLoaded = false;
  String? _fontLoadError;
  PdfExportError _lastError = PdfExportError.none;

  PdfExportService._();

  static PdfExportService get instance {
    _instance ??= PdfExportService._();
    return _instance!;
  }

  /// Clear cached fonts (useful for retry after error)
  void clearFontCache() {
    _arabicFont = null;
    _arabicBoldFont = null;
    _fontsLoaded = false;
    _fontLoadError = null;
    debugPrint('[PDF] Font cache cleared');
  }

  /// Load Arabic fonts from assets
  /// Uses Amiri font - a static TTF font that works with the pdf package
  Future<bool> _loadFonts() async {
    if (_fontsLoaded && _arabicFont != null && _arabicBoldFont != null) {
      debugPrint('[PDF] Using cached fonts');
      return true;
    }

    debugPrint('[PDF] Loading Arabic fonts...');

    try {
      // Load regular font
      debugPrint('[PDF] Loading Amiri-Regular.ttf...');
      final regularData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      debugPrint('[PDF] Regular font bytes length: ${regularData.lengthInBytes}');

      // Load bold font
      debugPrint('[PDF] Loading Amiri-Bold.ttf...');
      final boldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
      debugPrint('[PDF] Bold font bytes length: ${boldData.lengthInBytes}');

      // Create font objects
      _arabicFont = pw.Font.ttf(regularData);
      _arabicBoldFont = pw.Font.ttf(boldData);
      _fontsLoaded = true;
      _fontLoadError = null;

      debugPrint('[PDF] Arabic fonts loaded successfully');
      return true;
    } catch (e) {
      _fontLoadError = e.toString();
      debugPrint('[PDF] Error loading fonts: $e');
      return false;
    }
  }

  /// Export result to PDF and share
  ///
  /// Returns true if export and share was successful.
  Future<bool> exportAndShare({
    required String fileName,
    required String outputType,
    required String summaryLength,
    required GeneratedResult result,
    String pageRangeLabel = 'كل الصفحات',
    String outputLanguage = 'ar',
  }) async {
    _lastError = PdfExportError.none;

    debugPrint('[PDF] ========== Export Started ==========');
    debugPrint('[PDF] Original file name: $fileName');
    debugPrint('[PDF] Output type: $outputType');
    debugPrint('[PDF] Page range: $pageRangeLabel');
    debugPrint('[PDF] Language: $outputLanguage');

    // Step 1: Load fonts
    try {
      final fontsLoaded = await _loadFonts();
      if (!fontsLoaded) {
        _lastError = PdfExportError.fontLoadFailed;
        debugPrint('[PDF] ERROR: Font loading failed');
        debugPrint('[PDF] Font error: $_fontLoadError');
        return false;
      }
    } catch (e) {
      _lastError = PdfExportError.fontLoadFailed;
      debugPrint('[PDF] ERROR: Font loading exception: $e');
      return false;
    }

    // Step 2: Build PDF document
    Uint8List pdfBytes;
    try {
      debugPrint('[PDF] Building PDF document...');
      final pdf = pw.Document();

      // Add content pages (Arabic file name is used INSIDE the PDF content)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => _buildContent(
            fileName: fileName, // Original Arabic name displayed inside PDF
            outputType: outputType,
            summaryLength: summaryLength,
            outputLanguage: outputLanguage,
            result: result,
            pageRangeLabel: pageRangeLabel,
          ),
        ),
      );

      pdfBytes = await pdf.save();
      debugPrint('[PDF] PDF bytes generated: ${pdfBytes.length} bytes');

      if (pdfBytes.isEmpty) {
        _lastError = PdfExportError.pdfBuildFailed;
        debugPrint('[PDF] ERROR: PDF bytes are empty');
        return false;
      }
    } catch (e, stackTrace) {
      _lastError = PdfExportError.pdfBuildFailed;
      debugPrint('[PDF] ERROR: PDF build failed: $e');
      debugPrint('[PDF] Stack trace: $stackTrace');
      return false;
    }

    // Step 3: Save PDF file with SAFE English-only name
    File file;
    String safePdfName;
    try {
      // Use application documents directory (more reliable on real devices)
      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // IMPORTANT: Use English-only safe file name for the path
      // Arabic file name is displayed inside the PDF content, not in the path
      safePdfName = 'khulasah_result_$timestamp.pdf';
      final pdfPath = '${docsDir.path}/$safePdfName';

      debugPrint('[PDF] Safe file name: $safePdfName');
      debugPrint('[PDF] Save path: $pdfPath');

      file = File(pdfPath);
      await file.writeAsBytes(pdfBytes);

      // Verify file was saved correctly
      final fileExists = await file.exists();
      final fileSize = await file.length();

      debugPrint('[PDF] File exists: $fileExists');
      debugPrint('[PDF] File size: $fileSize bytes');

      if (!fileExists || fileSize == 0) {
        _lastError = PdfExportError.pdfSaveFailed;
        debugPrint('[PDF] ERROR: File verification failed');
        return false;
      }
    } catch (e, stackTrace) {
      _lastError = PdfExportError.pdfSaveFailed;
      debugPrint('[PDF] ERROR: PDF save failed: $e');
      debugPrint('[PDF] Stack trace: $stackTrace');
      return false;
    }

    // Step 4: Share the file
    try {
      debugPrint('[PDF] Share started...');

      final xFile = XFile(
        file.path,
        mimeType: 'application/pdf',
        name: safePdfName,
      );

      await Share.shareXFiles(
        [xFile],
        subject: 'خُلاصة - ملخص PDF',
        text: 'نتيجة تلخيص الملف من تطبيق خُلاصة',
      );

      debugPrint('[PDF] Share completed successfully');
      debugPrint('[PDF] ========== Export Completed ==========');
      return true;
    } catch (e, stackTrace) {
      _lastError = PdfExportError.pdfShareFailed;
      debugPrint('[PDF] ERROR: Share failed: $e');
      debugPrint('[PDF] Stack trace: $stackTrace');
      // PDF was created but sharing failed
      return false;
    }
  }

  /// Get user-friendly error message based on last error
  String getErrorMessage() {
    switch (_lastError) {
      case PdfExportError.fontLoadFailed:
        return 'تعذر تحميل الخطوط العربية';
      case PdfExportError.pdfBuildFailed:
        return 'تعذر إنشاء ملف PDF حاليًا، حاول مرة أخرى.';
      case PdfExportError.pdfSaveFailed:
        return 'تعذر حفظ ملف PDF، تأكد من وجود مساحة كافية.';
      case PdfExportError.pdfShareFailed:
        return 'تم إنشاء ملف PDF ولكن تعذر فتح المشاركة.';
      case PdfExportError.none:
        return 'تعذر إنشاء ملف PDF حاليًا، حاول مرة أخرى.';
    }
  }

  /// Get the last error code (for debugging)
  PdfExportError get lastError => _lastError;

  List<pw.Widget> _buildContent({
    required String fileName,
    required String outputType,
    required String summaryLength,
    required GeneratedResult result,
    String pageRangeLabel = 'كل الصفحات',
    String outputLanguage = 'ar',
  }) {
    final widgets = <pw.Widget>[];

    // Header with app name
    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#0F5132'),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'خُلاصة',
              style: pw.TextStyle(
                font: _arabicBoldFont,
                fontSize: 28,
                color: PdfColors.white,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'لخص ملفاتك ومستنداتك بسهولة',
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 12,
                color: PdfColors.white,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ),
    );

    widgets.add(pw.SizedBox(height: 24));

    // File info section
    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _buildInfoRow('اسم الملف:', fileName),
            pw.SizedBox(height: 8),
            _buildInfoRow('نطاق الصفحات:', pageRangeLabel),
            pw.SizedBox(height: 8),
            _buildInfoRow('نوع المخرجات:', _getOutputTypeLabel(outputType)),
            pw.SizedBox(height: 8),
            _buildInfoRow('طول الملخص:', _getSummaryLengthLabel(summaryLength)),
            pw.SizedBox(height: 8),
            _buildInfoRow('لغة النتيجة:', _getOutputLanguageLabel(outputLanguage)),
            pw.SizedBox(height: 8),
            _buildInfoRow('التاريخ:', _formatDate(DateTime.now())),
          ],
        ),
      ),
    );

    widgets.add(pw.SizedBox(height: 24));

    // Summary section
    if (result.hasSummary) {
      widgets.add(_buildSectionHeader('الملخص'));
      widgets.add(pw.SizedBox(height: 12));
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            result.summary!,
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 12,
              lineSpacing: 1.8,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.right,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 24));
    }

    // Q&A section
    if (result.hasQuestions) {
      widgets.add(_buildSectionHeader('الأسئلة والأجوبة'));
      widgets.add(pw.SizedBox(height: 12));

      for (var i = 0; i < result.questionsAndAnswers!.length; i++) {
        final qa = result.questionsAndAnswers![i];
        widgets.add(_buildQACard(i + 1, qa));
        widgets.add(pw.SizedBox(height: 12));
      }
    }

    // Footer
    widgets.add(pw.SizedBox(height: 24));
    widgets.add(
      pw.Container(
        width: double.infinity,
        child: pw.Text(
          'تم إنشاء هذا الملف بواسطة تطبيق خُلاصة',
          style: pw.TextStyle(
            font: _arabicFont,
            fontSize: 10,
            color: PdfColors.grey600,
          ),
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    return widgets;
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: 11,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.right,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          label,
          style: pw.TextStyle(
            font: _arabicBoldFont,
            fontSize: 11,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#0F5132'),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: _arabicBoldFont,
          fontSize: 14,
          color: PdfColors.white,
        ),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.right,
      ),
    );
  }

  pw.Widget _buildQACard(int index, QuestionAnswer qa) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  qa.question,
                  style: pw.TextStyle(
                    font: _arabicBoldFont,
                    fontSize: 11,
                  ),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                width: 24,
                height: 24,
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#0F5132'),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '$index',
                    style: pw.TextStyle(
                      font: _arabicBoldFont,
                      fontSize: 10,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              qa.answer,
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 10,
                lineSpacing: 1.5,
              ),
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _getOutputTypeLabel(String outputType) {
    switch (outputType) {
      case 'summary':
      case 'summaryOnly':
        return 'ملخص';
      case 'qa':
      case 'questionsOnly':
        return 'سؤال وجواب';
      case 'both':
      case 'summaryAndQuestions':
        return 'ملخص + أسئلة';
      default:
        return 'ملخص';
    }
  }

  String _getSummaryLengthLabel(String length) {
    switch (length) {
      case 'short':
        return 'قصير';
      case 'medium':
        return 'متوسط';
      case 'long':
        return 'طويل';
      case 'custom':
        return 'مخصص';
      default:
        return 'متوسط';
    }
  }

  String _getOutputLanguageLabel(String language) {
    switch (language) {
      case 'ar':
        return 'العربية';
      case 'en':
        return 'English';
      default:
        return 'العربية';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${_padZero(date.month)}/${_padZero(date.day)} ${_padZero(date.hour)}:${_padZero(date.minute)}';
  }

  String _padZero(int value) => value.toString().padLeft(2, '0');
}
