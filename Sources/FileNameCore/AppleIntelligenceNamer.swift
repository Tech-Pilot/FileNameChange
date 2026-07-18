import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Names PDFs with Apple's on-device foundation model — free, private,
/// no API key. Needs macOS 26+ with Apple Intelligence enabled, and the app
/// must be built with the macOS 26 SDK for this code to be compiled in.
enum AppleIntelligenceNamer {

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

    static func suggestName(from extraction: PDFExtraction, includeDate: Bool) async throws -> String {
        #if canImport(FoundationModels)
        if let reason = unavailabilityReason {
            throw NamingError.engineUnavailable(reason)
        }
        guard #available(macOS 26.0, *) else {
            // Unreachable: unavailabilityReason already covers this case, but
            // the compiler needs the availability guard.
            throw NamingError.engineUnavailable("Apple Intelligence naming needs macOS 26 or later.")
        }

        let prompt = NamingPrompt.userPrompt(for: extraction, excerptLimit: 2200) + "\n\nFile name:"
        let session = LanguageModelSession(instructions: NamingPrompt.rules(includeDate: includeDate))
        let response = try await session.respond(to: prompt)
        let cleaned = FilenameSanitizer.cleanAISuggestion(response.content)
        guard !cleaned.isEmpty else {
            throw NamingError.badResponse("Apple Intelligence returned an empty name.")
        }
        return cleaned
        #else
        throw NamingError.engineUnavailable(unavailabilityReason ?? "Apple Intelligence isn't available in this build.")
        #endif
    }
}
