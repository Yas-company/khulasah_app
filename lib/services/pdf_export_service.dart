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
  pw.MemoryImage? _logoImage;
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
    _logoImage = null;
    _fontsLoaded = false;
    _fontLoadError = null;
    debugPrint('[PDF] Font cache cleared');
  }

  /// Load Arabic fonts from assets
  /// Uses Amiri font - a static TTF font that works with the pdf package
  Future<bool> _loadFonts() async {
    if (_fontsLoaded &&
        _arabicFont != null &&
        _arabicBoldFont != null &&
        _logoImage != null) {
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

      debugPrint('[PDF] Loading logo...');
      final logoData = await rootBundle.load(
        'assets/images/khulasah_full_logo_horizontal_transparent.png',
      );
      debugPrint('[PDF] Logo bytes length: ${logoData.lengthInBytes}');

      // Create font objects
      _arabicFont = pw.Font.ttf(regularData);
      _arabicBoldFont = pw.Font.ttf(boldData);
      _logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
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
    required BuildContext context,
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
      final buildResult = await _buildBestFitPdf(
        fileName: fileName,
        outputType: outputType,
        summaryLength: summaryLength,
        outputLanguage: outputLanguage,
        result: result,
        pageRangeLabel: pageRangeLabel,
      );
      pdfBytes = buildResult.bytes;
      debugPrint('[PDF] Final page count: ${buildResult.pageCount}');
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

      final box = context.findRenderObject() as RenderBox?;

      await Share.shareXFiles(
        [xFile],
        subject: 'خُلاصة - ملخص PDF',
        text: 'نتيجة تلخيص الملف من تطبيق خُلاصة',
        sharePositionOrigin:
        box!.localToGlobal(Offset.zero) & box.size,
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

  Future<_PdfBuildResult> _buildBestFitPdf({
    required String fileName,
    required String outputType,
    required String summaryLength,
    required GeneratedResult result,
    required String pageRangeLabel,
    required String outputLanguage,
  }) async {
    final targetPageCount = _getTargetPageCount(summaryLength);
    final configs = _layoutConfigsForTarget(targetPageCount);
    _PdfBuildResult? bestResult;

    debugPrint('[PDF] Target page count: $targetPageCount');

    for (final config in configs) {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: pw.EdgeInsets.all(config.margin),
          build: (context) => _buildContent(
            fileName: fileName,
            outputType: outputType,
            summaryLength: summaryLength,
            outputLanguage: outputLanguage,
            result: result,
            pageRangeLabel: pageRangeLabel,
            layout: config,
          ),
        ),
      );

      final pageCount = pdf.document.pdfPageList.pages.length;
      debugPrint(
        '[PDF] Layout ${config.name}: pages=$pageCount, font=${config.summaryFontSize}, line=${config.summaryLineSpacing}, margin=${config.margin}',
      );

      final bytes = await pdf.save();
      final buildResult = _PdfBuildResult(
        bytes: bytes,
        pageCount: pageCount,
        layoutName: config.name,
      );

      if (targetPageCount == null || pageCount == targetPageCount) {
        debugPrint('[PDF] Selected layout: ${config.name}');
        return buildResult;
      }

      if (bestResult == null ||
          (pageCount - targetPageCount).abs() <
              (bestResult.pageCount - targetPageCount).abs()) {
        bestResult = buildResult;
      }
    }

    debugPrint('[PDF] Selected closest layout: ${bestResult!.layoutName}');
    return bestResult;
  }

  List<_PdfLayoutConfig> _layoutConfigsForTarget(int? targetPageCount) {
    const compact = _PdfLayoutConfig(
      name: 'compact',
      margin: 28,
      infoPadding: 10,
      sectionSpacing: 14,
      paragraphGap: 3,
      summaryFontSize: 9.5,
      summaryLineSpacing: 0.9,
      qaFontSize: 9.5,
      qaLineSpacing: 1.0,
    );
    const balanced = _PdfLayoutConfig(
      name: 'balanced',
      margin: 40,
      infoPadding: 16,
      sectionSpacing: 24,
      paragraphGap: 8,
      summaryFontSize: 12,
      summaryLineSpacing: 1.8,
      qaFontSize: 10,
      qaLineSpacing: 1.5,
    );
    const roomy = _PdfLayoutConfig(
      name: 'roomy',
      margin: 48,
      infoPadding: 18,
      sectionSpacing: 28,
      paragraphGap: 12,
      summaryFontSize: 13.5,
      summaryLineSpacing: 2.5,
      qaFontSize: 11,
      qaLineSpacing: 2.0,
    );
    const expanded = _PdfLayoutConfig(
      name: 'expanded',
      margin: 56,
      infoPadding: 20,
      sectionSpacing: 34,
      paragraphGap: 18,
      summaryFontSize: 15,
      summaryLineSpacing: 3.4,
      qaFontSize: 12,
      qaLineSpacing: 2.6,
    );
    const maximum = _PdfLayoutConfig(
      name: 'maximum',
      margin: 64,
      infoPadding: 22,
      sectionSpacing: 40,
      paragraphGap: 26,
      summaryFontSize: 16,
      summaryLineSpacing: 4.6,
      qaFontSize: 12.5,
      qaLineSpacing: 3.2,
    );

    if (targetPageCount == null) return [balanced];
    if (targetPageCount <= 1) return [balanced, compact];
    if (targetPageCount <= 5) {
      return [balanced, roomy, expanded, compact, maximum];
    }
    return [balanced, roomy, expanded, maximum, compact];
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
    _PdfLayoutConfig layout = const _PdfLayoutConfig(),
  }) {
    final widgets = <pw.Widget>[];

    // Header with app name
    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.all(layout.infoPadding),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#0F5132'),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 18,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Image(
                _logoImage!,
                width: 220,
                fit: pw.BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );

    widgets.add(pw.SizedBox(height: layout.sectionSpacing));

    // File info section
    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.all(layout.infoPadding),
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

    widgets.add(pw.SizedBox(height: layout.sectionSpacing));

    // Summary section - split into paragraphs for page spanning
    if (result.hasSummary) {
      widgets.add(_buildSectionHeader('الملخص'));
      widgets.add(pw.SizedBox(height: 12));

      // Split summary into paragraphs to allow page breaks
      final paragraphs = result.summary!.split('\n');
      for (final paragraph in paragraphs) {
        if (paragraph.trim().isNotEmpty) {
          widgets.add(
            pw.Paragraph(
              text: paragraph.trim(),
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: layout.summaryFontSize,
                lineSpacing: layout.summaryLineSpacing,
              ),
              textAlign: pw.TextAlign.right,
            ),
          );
          widgets.add(pw.SizedBox(height: layout.paragraphGap));
        }
      }
      widgets.add(pw.SizedBox(height: layout.sectionSpacing / 1.5));
    }

    // Q&A section
    if (result.hasQuestions) {
      widgets.add(_buildSectionHeader('الأسئلة والأجوبة'));
      widgets.add(pw.SizedBox(height: 12));

      for (var i = 0; i < result.questionsAndAnswers!.length; i++) {
        final qa = result.questionsAndAnswers![i];
        // Add all widgets from Q&A (allows page spanning)
        widgets.addAll(_buildQAWidgets(i + 1, qa, layout));
      }
    }

    // Footer
    widgets.add(pw.SizedBox(height: 24));
    widgets.add(
      pw.Container(
        width: double.infinity,
        child: pw.Text(
          'تم إنشاء هذا الملف بواسطة التطبيق',
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
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                font: _arabicBoldFont,
                fontSize: 11,
              ),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
          ),

          pw.Expanded(
            flex: 4,
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: _arabicFont,
                fontSize: 11,
              ),
              textAlign: pw.TextAlign.left,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
        ],
      ),
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

  /// Build Q&A section as a list of widgets (allows page spanning)
  List<pw.Widget> _buildQAWidgets(
    int index,
    QuestionAnswer qa,
    _PdfLayoutConfig layout,
  ) {
    final widgets = <pw.Widget>[];

    // Question number badge
    widgets.add(
      pw.Container(
        width: 28,
        height: 28,
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#0F5132'),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Center(
          child: pw.Text(
            'س$index',
            style: pw.TextStyle(
              font: _arabicBoldFont,
              fontSize: 10,
              color: PdfColors.white,
            ),
          ),
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 6));

    // Question text as Paragraph
    widgets.add(
      pw.Paragraph(
        text: qa.question,
            style: pw.TextStyle(
              font: _arabicBoldFont,
              fontSize: layout.qaFontSize + 1,
            ),
        textAlign: pw.TextAlign.right,
      ),
    );
    widgets.add(pw.SizedBox(height: 8));

    // Answer - split into paragraphs for long answers
    final answerParagraphs = qa.answer.split('\n');
    for (final paragraph in answerParagraphs) {
      if (paragraph.trim().isNotEmpty) {
        widgets.add(
          pw.Paragraph(
            text: paragraph.trim(),
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: layout.qaFontSize,
              lineSpacing: layout.qaLineSpacing,
            ),
            textAlign: pw.TextAlign.right,
          ),
        );
        widgets.add(pw.SizedBox(height: layout.paragraphGap / 2));
      }
    }

    widgets.add(pw.SizedBox(height: layout.paragraphGap));
    widgets.add(pw.Divider(color: PdfColors.grey300));
    widgets.add(pw.SizedBox(height: layout.paragraphGap));

    return widgets;
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
      case 'onePage':
      case 'short':
        return 'صفحة واحدة';
      case 'fivePages':
      case 'medium':
        return '5 صفحات';
      case 'tenPages':
      case 'long':
        return '10 صفحات';
      case 'custom':
        return 'مخصص';
      default:
        return 'متوسط';
    }
  }

  int? _getTargetPageCount(String length) {
    switch (length) {
      case 'onePage':
      case 'short':
        return 1;
      case 'fivePages':
      case 'medium':
        return 5;
      case 'tenPages':
      case 'long':
        return 10;
      default:
        return null;
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

class _PdfBuildResult {
  final Uint8List bytes;
  final int pageCount;
  final String layoutName;

  const _PdfBuildResult({
    required this.bytes,
    required this.pageCount,
    required this.layoutName,
  });
}

class _PdfLayoutConfig {
  final String name;
  final double margin;
  final double infoPadding;
  final double sectionSpacing;
  final double paragraphGap;
  final double summaryFontSize;
  final double summaryLineSpacing;
  final double qaFontSize;
  final double qaLineSpacing;

  const _PdfLayoutConfig({
    this.name = 'balanced',
    this.margin = 40,
    this.infoPadding = 16,
    this.sectionSpacing = 24,
    this.paragraphGap = 8,
    this.summaryFontSize = 12,
    this.summaryLineSpacing = 1.8,
    this.qaFontSize = 10,
    this.qaLineSpacing = 1.5,
  });
}
