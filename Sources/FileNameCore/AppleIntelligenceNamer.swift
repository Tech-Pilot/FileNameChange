import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Names PDFs with Apple's on-device foundation model — free, private,
/// no API key. Needs macOS 26+ with Apple Intelligence enabled, and the app
/// must be built with the macOS 26 SDK for this code to be compiled in.
enum AppleIntelligenceNamer {

    static let instructions = """
    You name PDF files based on their content. Reply with ONLY a file name base — no extension, no quotes, no explanations.
    Use 3 to 10 words that say what the document is: its type, subject, and who it involves. \
    If the document has one clearly primary date, start the name with it as YYYY-MM-DD followed by a space. \
    Use Title Case with normal spaces. Never use slashes, colons, quotes, or periods. \
    Write the name in the document's own language.
    """

    /// nil when the engine can run right now; otherwise a human-readable reason.
    static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return "Apple Intelligence naming needs macOS 26 or later."
        }
        if case .available = SystemLanguageModel.default.availability {
            return nil
        }
        return "Apple Intelligence isn't available on this Mac. It needs Apple silicon with Apple Intelligence turned on in System Settings."
        #else
        return "This build doesn't include Apple Intelligence support. Rebuild on macOS 26 with Xcode 26 (or current Command Line Tools) to enable it."
        #endif
    }

    static func suggestName(from extraction: PDFExtraction) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw NamingError.engineUnavailable("Apple Intelligence naming needs macOS 26 or later.")
        }
        if let reason = unavailabilityReason {
            throw NamingError.engineUnavailable(reason)
        }

        let excerpt = String(extraction.text.prefix(2200))
        var prompt = "Current file name: \(extraction.fileName).pdf\n"
        if let title = extraction.metadataTitle, !title.isEmpty {
            prompt += "PDF metadata title: \(title)\n"
        }
        prompt += "\nDocument text (first pages):\n\(excerpt)\n\nFile name:"

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let cleaned = FilenameSanitizer.cleanAISuggestion(response.content)
        guard !cleaned.isEmpty else {
            throw NamingError.badResponse("Apple Intelligence returned an empty name.")
        }
        return cleaned
        #else
        throw NamingError.engineUnavailable("This build doesn't include Apple Intelligence support.")
        #endif
    }
}
