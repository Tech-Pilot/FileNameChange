import Foundation
import NaturalLanguage

/// The built-in, fully offline naming engine. It combines the PDF's metadata,
/// typography, keywords, named entities, and dates into a descriptive name.
enum HeuristicNamer {

    struct Analysis {
        var title: String?
        var kind: DocumentKind?
        var organization: String?
        var person: String?
        var date: Date?
    }

    struct DocumentKind: Equatable {
        var label: String
        /// Transactional kinds (invoices, statements…) beat vague titles.
        var isStrong: Bool
    }

    // MARK: - Entry point

    static func suggest(from extraction: PDFExtraction, prefs: Preferences) -> (base: String, note: String) {
        let analysis = analyze(extraction)
        var (base, isWeak) = compose(analysis, extraction: extraction, prefs: prefs)

        base = FilenameSanitizer.applyStyle(to: base, caseStyle: prefs.caseStyle, separator: prefs.separator)
        base = FilenameSanitizer.sanitize(base)

        if base.isEmpty {
            base = extraction.fileName
            isWeak = true
        }

        var noteParts = ["Built-in analysis"]
        if extraction.usedOCR { noteParts.append("OCR used") }
        if isWeak { noteParts.append("low confidence — edit as needed") }
        return (base, noteParts.joined(separator: " · "))
    }

    // MARK: - Analysis

    static func analyze(_ extraction: PDFExtraction) -> Analysis {
        var analysis = Analysis()

        let cleanedMetadata = cleanMetadataTitle(extraction.metadataTitle, currentFileName: extraction.fileName)
        analysis.title = cleanedMetadata ?? validatedTitle(extraction.fontTitle) ?? firstGoodLine(in: extraction.text)
        analysis.kind = detectKind(in: extraction.text)
        analysis.organization = detectOrganization(in: extraction.text)
        analysis.person = detectPerson(in: extraction.text)
        analysis.date = detectDate(in: extraction.text)
        return analysis
    }

    static func compose(_ analysis: Analysis, extraction: PDFExtraction, prefs: Preferences) -> (base: String, isWeak: Bool) {
        var base: String?
        var cameFromParts = false
        var isWeak = false

        let personKinds = ["Resume", "CV", "Cover Letter", "Certificate"]

        if let kind = analysis.kind, personKinds.contains(kind.label), let person = analysis.person {
            base = "\(person) \(kind.label)"
            cameFromParts = true
        } else if let kind = analysis.kind, kind.isStrong {
            // "Acme Invoice", "Chase Bank Statement" — org + kind reads best
            // for transactional documents, even when a title-ish line exists.
            if let org = analysis.organization {
                base = orgKindName(org: org, kindLabel: kind.label)
            } else {
                base = analysis.title ?? kind.label
            }
            cameFromParts = true
        } else if let title = analysis.title {
            base = title
        } else if let kind = analysis.kind {
            if let org = analysis.organization {
                base = orgKindName(org: org, kindLabel: kind.label)
            } else {
                base = kind.label
            }
            cameFromParts = true
        } else if let org = analysis.organization {
            base = "\(org) Document"
            cameFromParts = true
            isWeak = true
        }

        guard var result = base, !result.isEmpty else {
            return (extraction.fileName, true)
        }

        result = truncateWords(result, maxWords: 12)

        // Date prefixes make transactional documents sort beautifully; they'd
        // just be noise in front of a real title.
        if cameFromParts, prefs.includeDate, let date = analysis.date {
            result = "\(isoDayFormatter.string(from: date)) \(result)"
        }
        return (result, isWeak)
    }

    static func orgKindName(org: String, kindLabel: String) -> String {
        if org.lowercased().contains(kindLabel.lowercased()) {
            return org
        }
        return "\(org) \(kindLabel)"
    }

    // MARK: - Titles

    static let genericTitles: [String] = [
        "untitled", "document", "documento", "new document", "scan", "scanned document",
        "img", "image", "doc1", "presentation", "slide 1", "layout 1", "book1",
        "blank", "draft", "final", "pdf", "microsoft word", "powerpoint presentation",
        "print", "output", "fullpage", "acrobat document", "adobe acrobat"
    ]

    static func isReasonableTitle(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 120 else { return false }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3 else { return false }
        guard Double(letters) / Double(trimmed.count) > 0.45 else { return false }

        let lowered = trimmed.lowercased()
        for generic in genericTitles where lowered == generic || lowered.hasPrefix(generic + " -") {
            return false
        }
        if lowered.hasSuffix(".pdf") || lowered.hasSuffix(".doc") || lowered.hasSuffix(".docx") {
            return false
        }
        return true
    }

    static func validatedTitle(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let cleaned = candidate
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isReasonableTitle(cleaned) ? cleaned : nil
    }

    /// PDF metadata titles are often junk like "Microsoft Word - report_v2.docx".
    /// Salvage what's salvageable, reject the rest.
    static func cleanMetadataTitle(_ raw: String?, currentFileName: String) -> String? {
        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        for prefix in ["microsoft word - ", "microsoft powerpoint - ", "microsoft excel - "] {
            if title.lowercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
            }
        }
        for ext in [".docx", ".doc", ".pptx", ".ppt", ".xlsx", ".xls", ".pdf", ".rtf", ".odt", ".pages", ".indd", ".qxd"] {
            if title.lowercased().hasSuffix(ext) {
                title = String(title.dropLast(ext.count))
            }
        }
        if !title.contains(" ") {
            title = title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }
        title = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A metadata title that's just the current file name tells us nothing new.
        if normalizedForComparison(title) == normalizedForComparison(currentFileName) {
            return nil
        }
        return isReasonableTitle(title) ? title : nil
    }

    static func normalizedForComparison(_ string: String) -> String {
        String(string.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// First line of the body text that looks like a heading rather than
    /// boilerplate (page numbers, addresses, URLs…).
    static func firstGoodLine(in text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(25)

        for line in lines {
            guard line.count >= 4, line.count <= 90 else { continue }
            let lowered = line.lowercased()
            if lowered.contains("@") || lowered.contains("http") || lowered.contains("www.") { continue }
            if lowered.range(of: "^(page|tel|fax|phone|email)\\b", options: .regularExpression) != nil { continue }
            if lowered.range(of: "^[\\d\\s\\-/.,:#]+$", options: .regularExpression) != nil { continue }
            guard isReasonableTitle(line) else { continue }
            return truncateWords(line, maxWords: 10)
        }
        return nil
    }

    static func truncateWords(_ string: String, maxWords: Int) -> String {
        let words = string.split(separator: " ")
        guard words.count > maxWords else { return string }
        return words.prefix(maxWords).joined(separator: " ")
    }

    // MARK: - Document kind

    struct KindRule {
        var label: String
        var isStrong: Bool
        var patterns: [(pattern: String, weight: Int)]
    }

    static let kindRules: [KindRule] = [
        KindRule(label: "Invoice", isStrong: true, patterns: [
            ("invoice", 3), ("invoice number", 3), ("bill to", 2), ("amount due", 2), ("total due", 2)
        ]),
        KindRule(label: "Receipt", isStrong: true, patterns: [
            ("receipt", 3), ("payment received", 2), ("thank you for your purchase", 2), ("order confirmation", 2)
        ]),
        KindRule(label: "Purchase Order", isStrong: true, patterns: [
            ("purchase order", 4)
        ]),
        KindRule(label: "Quote", isStrong: true, patterns: [
            ("quotation", 3), ("quote number", 3), ("price quote", 3)
        ]),
        KindRule(label: "Bank Statement", isStrong: true, patterns: [
            ("bank statement", 4), ("statement period", 3), ("opening balance", 2), ("closing balance", 2)
        ]),
        KindRule(label: "Statement", isStrong: true, patterns: [
            ("account statement", 3), ("statement of account", 3), ("billing statement", 3)
        ]),
        KindRule(label: "Payslip", isStrong: true, patterns: [
            ("payslip", 4), ("pay stub", 4), ("earnings statement", 4), ("net pay", 3), ("gross pay", 2)
        ]),
        KindRule(label: "Tax Form", isStrong: true, patterns: [
            ("form 1040", 4), ("w-2", 4), ("1099", 3), ("tax return", 4), ("internal revenue service", 3), ("taxable income", 2)
        ]),
        KindRule(label: "Boarding Pass", isStrong: true, patterns: [
            ("boarding pass", 5), ("boarding time", 3), ("boarding group", 3)
        ]),
        KindRule(label: "Lab Results", isStrong: true, patterns: [
            ("lab results", 4), ("test results", 3), ("reference range", 4), ("specimen", 3)
        ]),
        KindRule(label: "Prescription", isStrong: true, patterns: [
            ("prescription", 4), ("pharmacy", 2), ("refills", 2)
        ]),
        KindRule(label: "Insurance Policy", isStrong: true, patterns: [
            ("insurance policy", 4), ("policy number", 3), ("policyholder", 3), ("certificate of insurance", 4)
        ]),
        KindRule(label: "Travel Itinerary", isStrong: true, patterns: [
            ("itinerary", 4), ("booking confirmation", 4), ("reservation", 2), ("confirmation number", 2)
        ]),
        KindRule(label: "NDA", isStrong: false, patterns: [
            ("non-disclosure", 4), ("nondisclosure", 4), ("confidentiality agreement", 4)
        ]),
        KindRule(label: "Lease", isStrong: false, patterns: [
            ("lease agreement", 4), ("rental agreement", 4), ("landlord", 2), ("tenant", 2)
        ]),
        KindRule(label: "Contract", isStrong: false, patterns: [
            ("contract", 2), ("agreement", 2), ("hereinafter", 2), ("terms and conditions", 1)
        ]),
        KindRule(label: "Resume", isStrong: false, patterns: [
            ("curriculum vitae", 4), ("resume", 3), ("résumé", 4), ("professional experience", 2), ("work experience", 2)
        ]),
        KindRule(label: "Cover Letter", isStrong: false, patterns: [
            ("cover letter", 4), ("dear hiring manager", 4)
        ]),
        KindRule(label: "Report", isStrong: false, patterns: [
            ("annual report", 4), ("quarterly report", 4), ("executive summary", 2), ("report", 1)
        ]),
        KindRule(label: "Paper", isStrong: false, patterns: [
            ("abstract", 2), ("doi", 2), ("et al", 1), ("references", 1)
        ]),
        KindRule(label: "Manual", isStrong: false, patterns: [
            ("user manual", 4), ("user guide", 4), ("instruction manual", 4), ("installation guide", 3), ("quick start", 2)
        ]),
        KindRule(label: "Datasheet", isStrong: false, patterns: [
            ("datasheet", 4), ("spec sheet", 4), ("technical specifications", 3)
        ]),
        KindRule(label: "Certificate", isStrong: false, patterns: [
            ("certificate of", 4), ("hereby certifies", 4), ("certifies that", 4)
        ]),
        KindRule(label: "Meeting Minutes", isStrong: false, patterns: [
            ("meeting minutes", 4), ("minutes of the meeting", 4), ("action items", 2), ("attendees", 2)
        ]),
        KindRule(label: "Memo", isStrong: false, patterns: [
            ("memorandum", 4), ("memo to", 3)
        ]),
        KindRule(label: "Press Release", isStrong: false, patterns: [
            ("press release", 4), ("for immediate release", 5)
        ]),
        KindRule(label: "Newsletter", isStrong: false, patterns: [
            ("newsletter", 4)
        ]),
        KindRule(label: "Proposal", isStrong: false, patterns: [
            ("proposal", 3), ("scope of work", 3), ("statement of work", 3)
        ]),
        KindRule(label: "Syllabus", isStrong: false, patterns: [
            ("syllabus", 4), ("course outline", 4)
        ]),
        KindRule(label: "Transcript", isStrong: false, patterns: [
            ("official transcript", 4), ("academic transcript", 4)
        ]),
        KindRule(label: "Warranty", isStrong: false, patterns: [
            ("warranty", 3)
        ]),
        KindRule(label: "Letter", isStrong: false, patterns: [
            ("to whom it may concern", 3), ("sincerely", 1), ("dear ", 1)
        ])
    ]

    static func detectKind(in text: String) -> DocumentKind? {
        let lowered = String(text.prefix(6000)).lowercased()
        guard !lowered.isEmpty else { return nil }
        let head = String(lowered.prefix(300))

        var best: (rule: KindRule, score: Int)?
        for rule in kindRules {
            var score = 0
            for (pattern, weight) in rule.patterns {
                let occurrences = countOccurrences(of: pattern, in: lowered)
                if occurrences > 0 {
                    score += weight * min(occurrences, 3)
                    if head.contains(pattern) {
                        score += 3
                    }
                }
            }
            if score >= 3, score > (best?.score ?? 0) {
                best = (rule, score)
            }
        }
        guard let best else { return nil }
        return DocumentKind(label: best.rule.label, isStrong: best.rule.isStrong)
    }

    static func countOccurrences(of pattern: String, in text: String) -> Int {
        // Word boundaries keep short patterns from matching inside other words.
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let leading = pattern.first?.isLetter == true ? "\\b" : ""
        let last = pattern.last
        let trailing = (last?.isLetter == true || last?.isNumber == true) ? "\\b" : ""
        guard let regex = try? NSRegularExpression(pattern: leading + escaped + trailing, options: []) else { return 0 }
        return regex.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    // MARK: - Entities

    static let organizationStopWords: Set<String> = [
        "pdf", "inc", "llc", "ltd", "co", "gmbh", "the", "page", "invoice", "receipt", "total"
    ]

    static func detectOrganization(in text: String) -> String? {
        let sample = String(text.prefix(1500))
        guard !sample.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sample
        tagger.enumerateTags(
            in: sample.startIndex..<sample.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .organizationName {
                let name = String(sample[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2, name.count <= 40,
                   !organizationStopWords.contains(name.lowercased()) {
                    counts[name, default: 0] += 1
                    if firstSeen[name] == nil {
                        firstSeen[name] = order
                        order += 1
                    }
                }
            }
            return true
        }

        let ranked = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return (firstSeen[lhs.key] ?? 0) < (firstSeen[rhs.key] ?? 0)
        }
        if let top = ranked.first {
            return top.key
        }
        return organizationFromEmailDomain(in: sample)
    }

    static let publicEmailDomains: Set<String> = [
        "gmail", "yahoo", "outlook", "hotmail", "icloud", "aol", "proton", "protonmail", "live", "me", "mail"
    ]

    static func organizationFromEmailDomain(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+)\\.",
            options: []
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let domainRange = Range(match.range(at: 1), in: text) else { return nil }

        let domain = String(text[domainRange]).lowercased()
        guard domain.count >= 3, !publicEmailDomains.contains(domain) else { return nil }
        return domain.prefix(1).uppercased() + domain.dropFirst()
    }

    static func detectPerson(in text: String) -> String? {
        let sample = String(text.prefix(400))
        guard !sample.isEmpty else { return nil }

        var found: String?
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sample
        tagger.enumerateTags(
            in: sample.startIndex..<sample.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .personalName {
                let name = String(sample[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                let wordCount = name.split(separator: " ").count
                if wordCount >= 2, wordCount <= 3, name.count <= 40 {
                    found = name
                    return false
                }
            }
            return true
        }
        return found
    }

    // MARK: - Dates

    static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Picks the document's "main" date: prefers one sitting next to a label
    /// like "Invoice date:", otherwise the first plausible date in the text.
    static func detectDate(in text: String) -> Date? {
        let sample = String(text.prefix(3000))
        guard !sample.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        // Window right after a "… date:" label, if there is one.
        if let labelRegex = try? NSRegularExpression(
            pattern: "(invoice|statement|issue|issued|due|payment|order|report)?\\s*\\bdate\\b\\s*[:\\-]?\\s*",
            options: [.caseInsensitive]
        ) {
            let nsSample = sample as NSString
            let labelMatches = labelRegex.matches(in: sample, options: [], range: NSRange(location: 0, length: nsSample.length))
            for labelMatch in labelMatches {
                let start = labelMatch.range.location + labelMatch.range.length
                let length = min(40, nsSample.length - start)
                guard length > 4 else { continue }
                let window = nsSample.substring(with: NSRange(location: start, length: length))
                if let date = firstPlausibleDate(in: window, detector: detector) {
                    return date
                }
            }
        }

        return firstPlausibleDate(in: sample, detector: detector)
    }

    static func firstPlausibleDate(in text: String, detector: NSDataDetector) -> Date? {
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let lowerBound = calendar.date(byAdding: .year, value: -35, to: now),
              let upperBound = calendar.date(byAdding: .year, value: 2, to: now) else { return nil }

        for match in matches {
            guard let date = match.date else { continue }
            if date >= lowerBound && date <= upperBound {
                return date
            }
        }
        return nil
    }
}
