import Foundation
import PDFKit
import Vision
import AppKit

/// Vision-based text recognition for scanned PDFs (no text layer).
enum OCRService {
    /// Naming only needs the first stretch of text; once a page has yielded
    /// this much, later pages aren't worth another render + recognition pass.
    static let sufficientCharacters = 800

    /// Renders up to `maxPages` pages and runs accurate text recognition on them.
    /// Best-effort: returns whatever it managed to read, possibly "".
    static func recognizeText(in document: PDFDocument, maxPages: Int) -> String {
        var collected: [String] = []
        var collectedCount = 0

        for index in 0..<min(document.pageCount, maxPages) {
            guard collectedCount < sufficientCharacters else { break }
            guard let page = document.page(at: index) else { continue }

            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 1, bounds.height > 1 else { continue }

            // Render at roughly 200–300 dpi equivalent, capped for safety.
            let scale = min(4.0, max(1.0, 2200.0 / max(bounds.width, bounds.height)))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Without this, Vision assumes English and "corrects" other
            // languages toward English words.
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }

            let lines = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            if !lines.isEmpty {
                let pageText = lines.joined(separator: "\n")
                collected.append(pageText)
                collectedCount += pageText.count
            }
        }

        return collected.joined(separator: "\n")
    }
}
