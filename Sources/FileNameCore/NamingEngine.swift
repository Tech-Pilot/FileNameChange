import Foundation

/// Picks the configured engine, and falls back to the built-in analyzer
/// whenever an AI engine can't run — a drop should always produce a name.
enum NamingEngine {

    struct Result {
        var base: String
        var note: String
    }

    static func suggest(for extraction: PDFExtraction, prefs: Preferences) async -> Result {
        switch prefs.engine {
        case .builtin:
            return builtinResult(for: extraction, prefs: prefs)

        case .apple:
            do {
                let base = try await AppleIntelligenceNamer.suggestName(from: extraction, includeDate: prefs.includeDate)
                return Result(base: styled(base, prefs: prefs), note: note("Apple Intelligence", extraction: extraction))
            } catch {
                return fallback(for: extraction, prefs: prefs, engineName: "Apple Intelligence", error: error)
            }

        case .claude:
            let apiKey = KeychainStore.loadAPIKey()
            guard !apiKey.isEmpty else {
                return fallback(
                    for: extraction,
                    prefs: prefs,
                    engineName: "Claude",
                    error: NamingError.badResponse("no API key set — add one in Settings (⌘,)")
                )
            }
            do {
                let base = try await ClaudeNamer.suggestName(
                    from: extraction,
                    apiKey: apiKey,
                    model: prefs.claudeModel,
                    includeDate: prefs.includeDate
                )
                return Result(base: styled(base, prefs: prefs), note: note("Claude", extraction: extraction))
            } catch {
                return fallback(for: extraction, prefs: prefs, engineName: "Claude", error: error)
            }
        }
    }

    private static func builtinResult(for extraction: PDFExtraction, prefs: Preferences) -> Result {
        let (base, heuristicNote) = HeuristicNamer.suggest(from: extraction, prefs: prefs)
        return Result(base: base, note: heuristicNote)
    }

    private static func fallback(for extraction: PDFExtraction, prefs: Preferences, engineName: String, error: Error) -> Result {
        // Keep the heuristic's own note ("OCR used", "low confidence…") —
        // those flags matter most exactly when an engine failure forced the
        // fallback.
        let (base, heuristicNote) = HeuristicNamer.suggest(from: extraction, prefs: prefs)
        let reason = (error as? NamingError)?.errorDescription ?? error.localizedDescription
        return Result(base: base, note: "\(engineName) unavailable (\(reason)) — \(heuristicNote)")
    }

    private static func styled(_ base: String, prefs: Preferences) -> String {
        // Apply the user's case preference in full — including Title Case —
        // then the separator; sanitize last.
        let text = FilenameSanitizer.applyStyle(to: base, caseStyle: prefs.caseStyle, separator: prefs.separator)
        return FilenameSanitizer.sanitize(text)
    }

    private static func note(_ engineName: String, extraction: PDFExtraction) -> String {
        extraction.usedOCR ? "\(engineName) · OCR used" : engineName
    }
}
