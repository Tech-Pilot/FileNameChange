import Foundation

/// Turns arbitrary suggested text into a safe, tidy file name and finds
/// collision-free destinations on disk.
enum FilenameSanitizer {
    static let maxLength = 110

    /// Removes characters that are illegal or awkward in file names
    /// (macOS, Windows shares, cloud drives), collapses whitespace, and
    /// caps the length at a word boundary.
    static func sanitize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Newlines and whitespace runs become single spaces up front — the
        // control-character strip below would otherwise delete newlines
        // outright and merge the words around them.
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Path separators become hyphens so "Q3/Q4 Report" stays readable.
        text = text.replacingOccurrences(of: "/", with: "-")
        text = text.replacingOccurrences(of: "\\", with: "-")
        text = text.replacingOccurrences(of: ":", with: "-")

        // Strip characters that break Windows/SMB/cloud sync, plus control chars.
        let forbidden = CharacterSet(charactersIn: "<>|\"?*").union(.controlCharacters)
        text = String(text.unicodeScalars.filter { !forbidden.contains($0) }.map(Character.init))

        // No hidden files, no trailing dots/spaces.
        while text.hasPrefix(".") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        if text.count > maxLength {
            let cut = String(text.prefix(maxLength))
            if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > 60 {
                text = String(cut[..<lastSpace])
            } else {
                text = cut
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        }
        return text
    }

    static let smallWords: Set<String> = [
        "a", "an", "the", "and", "or", "nor", "but", "of", "to", "in", "on",
        "for", "at", "by", "with", "from", "as", "per"
    ]

    /// Applies the user's case and separator preferences.
    static func applyStyle(to input: String, caseStyle: CaseStyle, separator: SeparatorStyle) -> String {
        var text = input

        switch caseStyle {
        case .asIs:
            break
        case .lowercase:
            text = text.lowercased()
        case .titleCase:
            text = titleCased(text)
        }

        switch separator {
        case .spaces:
            break
        case .hyphens:
            text = text.replacingOccurrences(of: " ", with: "-")
        case .underscores:
            text = text.replacingOccurrences(of: " ", with: "_")
        }
        return text
    }

    /// Title Case that leaves acronyms alone and keeps small words lowered
    /// (except at the start and end).
    static func titleCased(_ input: String) -> String {
        let words = input.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return input }

        var result: [String] = []
        for (index, word) in words.enumerated() {
            let isEdge = index == 0 || index == words.count - 1
            let lowered = word.lowercased()

            if word.count >= 2, word == word.uppercased(), word.rangeOfCharacter(from: .letters) != nil {
                result.append(word) // acronym: PDF, IRS, Q3…
            } else if !isEdge, smallWords.contains(lowered) {
                result.append(lowered)
            } else {
                result.append(word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return result.joined(separator: " ")
    }

    /// Cleans up whatever an AI model returned: quotes, code fences,
    /// "Filename:" prefixes, stray extensions.
    static func cleanAISuggestion(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep just the first non-empty line.
        if let firstLine = text.components(separatedBy: .newlines).first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            text = firstLine.trimmingCharacters(in: .whitespaces)
        }

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))

        for prefix in ["filename:", "file name:", "name:", "suggested filename:"] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if text.lowercased().hasSuffix(".pdf") {
            text = String(text.dropLast(4))
        }
        return sanitize(text)
    }

    /// Candidate names for collision handling: "Base", "Base 2", "Base 3"…
    static func candidateNames(base: String, attempt: Int) -> String {
        attempt <= 1 ? base : "\(base) \(attempt)"
    }

    /// First non-existing URL in the file's directory for the given base name.
    static func availableURL(in directory: URL, base: String, pathExtension: String) throws -> URL {
        let fileManager = FileManager.default
        for attempt in 1...200 {
            let name = candidateNames(base: base, attempt: attempt)
            let candidate = directory
                .appendingPathComponent(name)
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw NSError(
            domain: "FileNameChange",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Too many files already share this name."]
        )
    }
}
