import Foundation
import PDFKit
import Vision
import AppKit

/// Vision-based text recognition for scanned PDFs (no text layer).
enum OCRService {
    /// Renders up to `maxPages` pages and runs accurate text recognition on them.
    /// Best-effort: returns whatever it managed to read, possibly "".
    static func recognizeText(in document: PDFDocument, maxPages: Int) -> String {
        var collected: [String] = []

        for index in 0..<min(document.pageCount, maxPages) {
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
                collected.append(lines.joined(separator: "\n"))
            }
        }

        return collected.joined(separator: "\n")
    }
}
