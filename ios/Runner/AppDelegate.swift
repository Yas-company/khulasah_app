import UIKit
import Flutter
import Vision
import PDFKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register OcrPlugin for Apple Vision text recognition
    let controller = window?.rootViewController as! FlutterViewController
    OcrPlugin.register(with: controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - OcrPlugin

/// Flutter plugin for on-device text recognition using Apple Vision framework.
/// Supports Arabic and English text recognition.
/// Uses PDFKit for native PDF rendering and Vision for OCR.
class OcrPlugin: NSObject {

    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.khulasah.ocr/vision",
            binaryMessenger: messenger
        )
        super.init()
        channel.setMethodCallHandler(handle)
    }

    static func register(with messenger: FlutterBinaryMessenger) {
        _ = OcrPlugin(messenger: messenger)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            // Vision framework is available on iOS 13+
            if #available(iOS 13.0, *) {
                result(true)
            } else {
                result(false)
            }

        case "recognizeText":
            guard let args = call.arguments as? [String: Any],
                  let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing image bytes", details: nil))
                return
            }
            recognizeText(from: imageBytes.data, result: result)

        case "recognizeTextFromPdfPages":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String,
                  let fromPage = args["fromPage"] as? Int,
                  let toPage = args["toPage"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
                return
            }
            recognizeTextFromPdfPages(filePath: filePath, fromPage: fromPage, toPage: toPage, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - PDF Pages OCR

    private func recognizeTextFromPdfPages(filePath: String, fromPage: Int, toPage: Int, result: @escaping FlutterResult) {
        NSLog("[OCR] Native PDFKit opening PDF: %@", filePath)

        // Try to open PDF document
        var pdfDocument: PDFDocument?

        // First try opening from URL
        let fileURL = URL(fileURLWithPath: filePath)
        pdfDocument = PDFDocument(url: fileURL)

        // If that fails, try opening from Data
        if pdfDocument == nil {
            NSLog("[OCR] PDFKit URL open failed, trying Data")
            do {
                let data = try Data(contentsOf: fileURL)
                pdfDocument = PDFDocument(data: data)
            } catch {
                NSLog("[OCR] PDFKit failed: %@", error.localizedDescription)
                result(FlutterError(code: "PDF_OPEN_FAILED", message: "Could not open PDF for image processing", details: error.localizedDescription))
                return
            }
        }

        guard let document = pdfDocument else {
            NSLog("[OCR] PDFKit failed: Could not create PDFDocument")
            result(FlutterError(code: "PDF_OPEN_FAILED", message: "Could not open PDF for image processing", details: nil))
            return
        }

        let pageCount = document.pageCount
        NSLog("[OCR] PDFKit opened PDF with %d pages", pageCount)

        // Validate page range (Flutter uses 1-based, PDFKit uses 0-based)
        let startIndex = max(0, fromPage - 1)
        let endIndex = min(pageCount - 1, toPage - 1)

        if startIndex > endIndex || startIndex >= pageCount {
            result(FlutterError(code: "INVALID_RANGE", message: "Invalid page range", details: nil))
            return
        }

        NSLog("[OCR] Processing pages %d to %d (0-indexed: %d to %d)", fromPage, toPage, startIndex, endIndex)

        // Process pages in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if #available(iOS 13.0, *) {
                self.processPages(document: document, startIndex: startIndex, endIndex: endIndex, result: result)
            } else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "UNAVAILABLE", message: "Text recognition requires iOS 13+", details: nil))
                }
            }
        }
    }

    @available(iOS 13.0, *)
    private func processPages(document: PDFDocument, startIndex: Int, endIndex: Int, result: @escaping FlutterResult) {
        var allRecognizedText: [String] = []
        let totalPages = endIndex - startIndex + 1
        let group = DispatchGroup()

        // Array to store results in order
        var pageTexts = [Int: String]()
        let lock = NSLock()

        for pageIndex in startIndex...endIndex {
            guard let page = document.page(at: pageIndex) else {
                NSLog("[OCR] Could not get page at index %d", pageIndex)
                continue
            }

            group.enter()

            let pageNum = pageIndex + 1 // 1-based for logging
            NSLog("[OCR] Rendering page: %d", pageNum)

            // Render page to image
            guard let pageImage = renderPageToImage(page: page) else {
                NSLog("[OCR] Failed to render page %d", pageNum)
                group.leave()
                continue
            }

            guard let cgImage = pageImage.cgImage else {
                NSLog("[OCR] Failed to get CGImage for page %d", pageNum)
                group.leave()
                continue
            }

            // Perform OCR on the rendered image
            let request = VNRecognizeTextRequest { request, error in
                defer { group.leave() }

                if let error = error {
                    NSLog("[OCR] Vision error on page %d: %@", pageNum, error.localizedDescription)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }

                let pageText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                if !pageText.isEmpty {
                    NSLog("[OCR] Vision recognized %d chars on page %d", pageText.count, pageNum)
                    lock.lock()
                    pageTexts[pageIndex] = pageText
                    lock.unlock()
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            if #available(iOS 14.0, *) {
                request.recognitionLanguages = ["ar", "en-US"]
            } else {
                request.recognitionLanguages = ["en-US"]
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("[OCR] Handler error on page %d: %@", pageNum, error.localizedDescription)
                group.leave()
            }
        }

        // Wait for all pages to complete
        group.wait()

        // Combine results in page order
        for pageIndex in startIndex...endIndex {
            if let text = pageTexts[pageIndex] {
                allRecognizedText.append(text)
            }
        }

        let combinedText = allRecognizedText.joined(separator: "\n\n")
        NSLog("[OCR] Native OCR total chars: %d", combinedText.count)

        DispatchQueue.main.async {
            result(combinedText)
        }
    }

    private func renderPageToImage(page: PDFPage) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)

        // Render at 2x scale for better OCR accuracy
        let scale: CGFloat = 2.0
        let renderRect = CGRect(
            x: 0,
            y: 0,
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: renderRect.size)

        let image = renderer.image { context in
            // Fill white background
            UIColor.white.setFill()
            context.fill(renderRect)

            // Scale and flip the context for PDF rendering
            context.cgContext.translateBy(x: 0, y: renderRect.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            // Draw the PDF page
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        return image
    }

    // MARK: - Image OCR (kept for compatibility)

    private func recognizeText(from imageData: Data, result: @escaping FlutterResult) {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            result(FlutterError(code: "INVALID_IMAGE", message: "Could not create image from data", details: nil))
            return
        }

        if #available(iOS 13.0, *) {
            performTextRecognition(on: cgImage, result: result)
        } else {
            result(FlutterError(code: "UNAVAILABLE", message: "Text recognition requires iOS 13+", details: nil))
        }
    }

    @available(iOS 13.0, *)
    private func performTextRecognition(on cgImage: CGImage, result: @escaping FlutterResult) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(code: "RECOGNITION_ERROR", message: error.localizedDescription, details: nil))
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    result("")
                }
                return
            }

            // Extract text from all observations
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")

            DispatchQueue.main.async {
                result(recognizedText)
            }
        }

        // Configure recognition settings
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Set recognition languages - Arabic and English
        if #available(iOS 14.0, *) {
            request.recognitionLanguages = ["ar", "en-US"]
        } else {
            request.recognitionLanguages = ["en-US"]
        }

        // Perform the request
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "HANDLER_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
}
