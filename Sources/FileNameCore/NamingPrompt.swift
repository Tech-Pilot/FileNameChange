import Foundation

/// The prompt text shared by every AI naming engine, so the two engines can't
/// drift apart — and so user preferences shape the instructions in one place.
enum NamingPrompt {

    /// System-level naming rules. The date instruction follows the user's
    /// "include date" preference instead of being hardcoded.
    static func rules(includeDate: Bool) -> String {
        var lines = [
            "You name PDF files based on their content. Reply with ONLY a file name base — no extension, no quotes, no explanations, nothing else.",
            "",
            "Rules:",
            "- 3 to 10 words that say what the document is: its type, subject, and who it involves.",
            "- Include the company, institution, or person the document is about when that helps identify it.",
            "- Use Title Case with normal spaces. Never use slashes, colons, quotes, or periods.",
            "- Write the name in the document's own language."
        ]
        if includeDate {
            lines.insert("- If the document has one clearly primary date (invoice date, statement date, letter date), start with it as YYYY-MM-DD followed by a space.", at: 4)
        } else {
            lines.insert("- Never start the name with a date.", at: 4)
        }
        return lines.joined(separator: "\n")
    }

    /// The per-document prompt: current name, metadata title, and a text
    /// excerpt capped at `excerptLimit` characters.
    static func userPrompt(for extraction: PDFExtraction, excerptLimit: Int) -> String {
        let excerpt = String(extraction.text.prefix(excerptLimit))
        var prompt = "Current file name: \(extraction.fileName).pdf\n"
        if let title = extraction.metadataTitle, !title.isEmpty {
            prompt += "PDF metadata title: \(title)\n"
        }
        prompt += "\nDocument text (first pages):\n\(excerpt)"
        if excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n(No text could be extracted from this PDF.)"
        }
        return prompt
    }
}
