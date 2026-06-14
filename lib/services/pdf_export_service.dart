import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/generated_result.dart';

/// Service for exporting results to PDF and sharing.
///
/// Creates Arabic-friendly PDF documents with:
/// - Arabic font support (Cairo)
/// - RTL text direction
/// - App branding
/// - File information
/// - Generated summary
/// - Questions and answers
class PdfExportService {
  static PdfExportService? _instance;

  // Cached fonts
  pw.Font? _arabicFont;
  pw.Font? _arabicBoldFont;

  PdfExportService._();

  static PdfExportService get instance {
    _instance ??= PdfExportService._();
    return _instance!;
  }

  /// Load Arabic fonts from assets
  Future<void> _loadFonts() async {
    if (_arabicFont != null && _arabicBoldFont != null) {
      return; // Fonts already loaded
    }

    debugPrint('[PDF] Loading Arabic fonts...');

    try {
      final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');

      _arabicFont = pw.Font.ttf(regularData);
      _arabicBoldFont = pw.Font.ttf(boldData);

      debugPrint('[PDF] Arabic fonts loaded successfully');
    } catch (e) {
      debugPrint('[PDF] Error loading fonts: $e');
      rethrow;
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
  }) async {
    debugPrint('[PDF] Export started');

    try {
      // Load fonts first
      await _loadFonts();

      // Create PDF document
      final pdf = pw.Document();

      // Add content pages
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => _buildContent(
            fileName: fileName,
            outputType: outputType,
            summaryLength: summaryLength,
            result: result,
          ),
        ),
      );

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final pdfPath = '${tempDir.path}/khulasah_${sanitizedFileName}_$timestamp.pdf';

      // Save PDF file
      final file = File(pdfPath);
      await file.writeAsBytes(await pdf.save());

      debugPrint('[PDF] File saved: $pdfPath');

      // Share the file
      final xFile = XFile(pdfPath);
      await Share.shareXFiles(
        [xFile],
        subject: 'خُلاصة - $fileName',
        text: 'نتيجة تلخيص الملف من تطبيق خُلاصة',
      );

      debugPrint('[PDF] Export completed successfully');
      return true;
    } catch (e) {
      debugPrint('[PDF] Export failed: $e');
      return false;
    }
  }

  List<pw.Widget> _buildContent({
    required String fileName,
    required String outputType,
    required String summaryLength,
    required GeneratedResult result,
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
            _buildInfoRow('نوع المخرجات:', _getOutputTypeLabel(outputType)),
            pw.SizedBox(height: 8),
            _buildInfoRow('طول الملخص:', _getSummaryLengthLabel(summaryLength)),
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

  String _formatDate(DateTime date) {
    return '${date.year}/${_padZero(date.month)}/${_padZero(date.day)} ${_padZero(date.hour)}:${_padZero(date.minute)}';
  }

  String _padZero(int value) => value.toString().padLeft(2, '0');
}
