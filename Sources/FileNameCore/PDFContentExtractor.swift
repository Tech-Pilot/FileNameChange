import Foundation
import PDFKit
import AppKit

/// Everything we managed to learn about a PDF's content.
public struct PDFExtraction {
    public var fileName: String
    public var metadataTitle: String?
    /// Title guessed from the largest text on page one.
    public var fontTitle: String?
    /// Plain text of the first few pages.
    public var text: String
    public var pageCount: Int
    public var usedOCR: Bool
}

enum ExtractionError: LocalizedError {
    case cannotOpen
    case passwordProtected

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "Couldn't open this file as a PDF."
        case .passwordProtected:
            return "This PDF is password-protected, so its contents can't be read."
        }
    }
}

enum PDFContentExtractor {
    static let maxPagesToRead = 5
    static let maxCharacters = 12_000

    /// Reads the PDF off the main thread and returns what it found.
    /// Falls back to OCR (Vision) when the PDF has no usable text layer.
    static func extract(url: URL) async throws -> PDFExtraction {
        try await Task.detached(priority: .userInitiated) {
            try extractSync(url: url)
        }.value
    }

    static func extractSync(url: URL) throws -> PDFExtraction {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpen
        }
        if document.isLocked {
            // PDFDocument already tried the empty password during init.
            throw ExtractionError.passwordProtected
        }

        let pageCount = document.pageCount
        var text = ""
        for index in 0..<min(pageCount, maxPagesToRead) {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            text += pageText + "\n"
            if text.count >= maxCharacters { break }
        }
        text = String(text.prefix(maxCharacters))

        var fontTitle: String?
        if let firstPage = document.page(at: 0) {
            fontTitle = fontBasedTitle(page: firstPage)
        }

        let metadataTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String

        // A near-empty text layer usually means a scanned document: try OCR.
        var usedOCR = false
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            let recognized = OCRService.recognizeText(in: document, maxPages: 2)
            if recognized.trimmingCharacters(in: .whitespacesAndNewlines).count > text.count {
                text = String(recognized.prefix(maxCharacters))
                usedOCR = true
            }
        }

        return PDFExtraction(
            fileName: url.deletingPathExtension().lastPathComponent,
            metadataTitle: metadataTitle,
            fontTitle: fontTitle,
            text: text,
            pageCount: pageCount,
            usedOCR: usedOCR
        )
    }

    /// Looks at page one and picks the line(s) set in the largest font —
    /// in most documents that's the title.
    static func fontBasedTitle(page: PDFPage) -> String? {
        guard let attributed = page.attributedString, attributed.length > 0 else { return nil }

        let ns = attributed.string as NSString
        let scanLength = min(ns.length, 4000)
        guard scanLength > 0 else { return nil }
        let scanRange = NSRange(location: 0, length: scanLength)

        // Collect font-size runs.
        var runs: [(range: NSRange, size: CGFloat)] = []
        attributed.enumerateAttribute(.font, in: scanRange, options: []) { value, range, _ in
            if let font = value as? NSFont {
                runs.append((range, font.pointSize))
            }
        }
        guard !runs.isEmpty else { return nil }

        // Split the scanned region into lines, keeping their ranges.
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: scanRange, options: .byLines) { substring, substringRange, _, stop in
            if let substring, !substring.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append((substring, substringRange))
            }
            if lines.count >= 30 {
                stop.pointee = true
            }
        }
        guard !lines.isEmpty else { return nil }

        // Max font size seen on each line.
        var lineSizes: [CGFloat] = []
        for line in lines {
            var maxSize: CGFloat = 0
            for run in runs where NSIntersectionRange(run.range, line.range).length > 0 {
                maxSize = max(maxSize, run.size)
            }
            lineSizes.append(maxSize)
        }

        guard let biggest = lineSizes.max(), biggest > 0 else { return nil }
        let sorted = lineSizes.filter { $0 > 0 }.sorted()
        let median = sorted[sorted.count / 2]

        // The "title" needs to stand out from the body text.
        guard biggest >= 13, biggest >= median + 2 || biggest >= 17 else { return nil }

        // Take the first run of consecutive lines at (about) the biggest size,
        // so wrapped titles come through whole.
        guard let start = lineSizes.firstIndex(where: { $0 >= biggest - 0.5 }) else { return nil }
        var pieces: [String] = []
        var index = start
        while index < lines.count, lineSizes[index] >= biggest - 0.5, pieces.count < 3 {
            pieces.append(lines[index].text.trimmingCharacters(in: .whitespaces))
            index += 1
        }

        let candidate = pieces.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return HeuristicNamer.isReasonableTitle(candidate) ? candidate : nil
    }
}
