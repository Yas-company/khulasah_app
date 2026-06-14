import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfExtractionResult {
  final String? text;
  final String? errorMessage;
  final bool success;

  const PdfExtractionResult._({
    this.text,
    this.errorMessage,
    required this.success,
  });

  factory PdfExtractionResult.success(String text) {
    return PdfExtractionResult._(
      text: text,
      success: true,
    );
  }

  factory PdfExtractionResult.empty() {
    return const PdfExtractionResult._(
      errorMessage: 'لم يتم العثور على نص داخل الملف. قد يكون الملف عبارة عن صور ممسوحة ضوئياً.',
      success: false,
    );
  }

  factory PdfExtractionResult.error(String message) {
    return PdfExtractionResult._(
      errorMessage: message,
      success: false,
    );
  }

  factory PdfExtractionResult.noPath() {
    return const PdfExtractionResult._(
      errorMessage: 'مسار الملف غير متوفر',
      success: false,
    );
  }
}

class PdfTextService {
  Future<PdfExtractionResult> extractText(String? filePath) async {
    // Check if file path is null
    if (filePath == null || filePath.isEmpty) {
      return PdfExtractionResult.noPath();
    }

    try {
      // Read the PDF file
      final file = File(filePath);

      if (!await file.exists()) {
        return PdfExtractionResult.error('الملف غير موجود');
      }

      final bytes = await file.readAsBytes();

      // Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // Extract text from all pages
      final StringBuffer extractedText = StringBuffer();

      for (int i = 0; i < document.pages.count; i++) {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);

        if (pageText.isNotEmpty) {
          extractedText.writeln(pageText);
        }
      }

      // Dispose the document
      document.dispose();

      final String resultText = extractedText.toString().trim();

      // Check if extracted text is empty
      if (resultText.isEmpty) {
        return PdfExtractionResult.empty();
      }

      return PdfExtractionResult.success(resultText);
    } catch (e) {
      return PdfExtractionResult.error('حدث خطأ أثناء استخراج النص: ${e.toString()}');
    }
  }
}
