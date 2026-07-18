import Foundation

/// Turns arbitrary suggested text into a safe, tidy file name and finds
/// collision-free destinations on disk.
enum FilenameSanitizer {
    static let maxLength = 110

    /// Collapses every whitespace run (including newlines) into a single space.
    static func collapseWhitespace(_ input: String) -> String {
        input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Characters that are illegal or unsafe in file names across macOS,
    /// Windows shares, and cloud drives: the Windows-forbidden set, C0/DEL
    /// control characters, and bidi-override characters (which can visually
    /// spoof a name). Format characters like ZWJ/ZWNJ are deliberately kept —
    /// they are legal in file names and removing them corrupts emoji
    /// sequences and Persian/Arabic orthography.
    private static let forbiddenScalars: CharacterSet = {
        var set = CharacterSet(charactersIn: "<>|\"?*")
        set.insert(charactersIn: UnicodeScalar(0x00)!...UnicodeScalar(0x1F)!)
        set.insert(UnicodeScalar(0x7F)!)
        set.insert(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        return set
    }()

    /// Names Windows reserves for devices, with or without an extension.
    static let reservedWindowsNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for number in 1...9 {
            names.insert("COM\(number)")
            names.insert("LPT\(number)")
        }
        return names
    }()

    /// Removes characters that are illegal or awkward in file names
    /// (macOS, Windows shares, cloud drives), collapses whitespace, and
    /// caps the length at a word boundary.
    static func sanitize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Newlines and whitespace runs become single spaces up front — the
        // control-character strip below would otherwise delete newlines
        // outright and merge the words around them.
        text = collapseWhitespace(text)

        // Path separators become hyphens so "Q3/Q4 Report" stays readable.
        text = text.replacingOccurrences(of: "/", with: "-")
        text = text.replacingOccurrences(of: "\\", with: "-")
        text = text.replacingOccurrences(of: ":", with: "-")

        text = String(text.unicodeScalars.filter { !forbiddenScalars.contains($0) }.map(Character.init))

        // No hidden files, no trailing dots/spaces.
        while text.hasPrefix(".") { text.removeFirst() }
        text = collapseWhitespace(text)
        text = text.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        if text.count > maxLength {
            let cut = String(text.prefix(maxLength))
            // Word boundaries can be spaces, hyphens, or underscores depending
            // on the user's separator preference.
            if let boundary = cut.lastIndex(where: { $0 == " " || $0 == "-" || $0 == "_" }),
               cut.distance(from: cut.startIndex, to: boundary) > 60 {
                text = String(cut[..<boundary])
            } else {
                text = cut
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        }

        if reservedWindowsNames.contains(text.uppercased()) {
            text += " File"
        }
        return text
    }

    /// Drops one trailing ".pdf" so pasting a full file name into the base
    /// field doesn't produce "Name.pdf.pdf".
    static func strippingPDFExtension(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".pdf") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
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
        text = strippingPDFExtension(text)
        return sanitize(text)
    }

    /// Candidate names for collision handling: "Base", "Base 2", "Base 3"…
    static func candidateNames(base: String, attempt: Int) -> String {
        attempt <= 1 ? base : "\(base) \(attempt)"
    }

    /// First non-existing URL in the file's directory for the given base name.
    ///
    /// `movingFrom` is the file being renamed: a candidate that is the same
    /// file (differing only by case on case-insensitive volumes) is not a
    /// collision — otherwise a capitalization-only rename would get a
    /// spurious " 2" suffix.
    static func availableURL(
        in directory: URL,
        base: String,
        pathExtension: String,
        movingFrom source: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let sourcePath = source?.standardizedFileURL.path

        for attempt in 1...200 {
            let name = candidateNames(base: base, attempt: attempt)
            let candidate = directory
                .appendingPathComponent(name)
                .appendingPathExtension(pathExtension)

            if let sourcePath,
               candidate.standardizedFileURL.path.compare(sourcePath, options: .caseInsensitive) == .orderedSame {
                return candidate
            }
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
