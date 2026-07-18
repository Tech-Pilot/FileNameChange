import XCTest
@testable import FileNameCore

final class HeuristicNamerTests: XCTestCase {

    func testCleanMetadataTitleSalvagesWordExports() {
        let result = HeuristicNamer.cleanMetadataTitle(
            "Microsoft Word - Q3_Sales_Report.docx",
            currentFileName: "scan_0042"
        )
        XCTAssertEqual(result, "Q3 Sales Report")
    }

    func testCleanMetadataTitleRejectsGenericAndFileNameEcho() {
        XCTAssertNil(HeuristicNamer.cleanMetadataTitle("Untitled", currentFileName: "doc"))
        XCTAssertNil(HeuristicNamer.cleanMetadataTitle("scan-0042", currentFileName: "scan_0042"))
        XCTAssertNil(HeuristicNamer.cleanMetadataTitle(nil, currentFileName: "doc"))
    }

    func testDetectKindInvoice() {
        let text = """
        INVOICE
        Invoice Number: INV-2041
        Bill To: Jane Smith
        Amount Due: $1,250.00
        """
        let kind = HeuristicNamer.detectKind(in: text)
        XCTAssertEqual(kind?.label, "Invoice")
        XCTAssertEqual(kind?.isStrong, true)
    }

    func testDetectKindResume() {
        let text = """
        JANE DOE
        Curriculum Vitae
        Professional Experience
        Education
        """
        let kind = HeuristicNamer.detectKind(in: text)
        XCTAssertEqual(kind?.label, "Resume")
    }

    func testDetectKindNothingObvious() {
        XCTAssertNil(HeuristicNamer.detectKind(in: "just a few plain words here"))
    }

    func testWordBoundariesPreventFalseMatches() {
        XCTAssertEqual(HeuristicNamer.countOccurrences(of: "resume", in: "he resumed working"), 0)
        XCTAssertEqual(HeuristicNamer.countOccurrences(of: "invoice", in: "invoice invoices"), 1)
    }

    func testDigitPatternsNeedBoundariesToo() {
        // "1099" must not match inside a longer number like an order ID.
        XCTAssertEqual(HeuristicNamer.countOccurrences(of: "1099", in: "order 31099 ships in july"), 0)
        XCTAssertEqual(HeuristicNamer.countOccurrences(of: "1099", in: "form 1099 attached"), 1)
    }

    func testDetectDatePrefersLabeledDate() {
        let text = """
        Some Corp
        Payment due within 30 days of December 31, 2030.
        Invoice Date: March 3, 2024
        """
        let detected = HeuristicNamer.detectDate(in: text)
        XCTAssertNotNil(detected)
        if let detected {
            XCTAssertEqual(HeuristicNamer.isoDayString(from: detected), "2024-03-03")
        }
    }

    func testDetectDateRejectsTimeOnlyMatches() {
        // A bare time resolves to "today", which would stamp the scan date
        // on the file instead of the document's own date.
        XCTAssertNil(HeuristicNamer.detectDate(in: "Check-out 11:00 AM\nThank you for staying with us"))
    }

    func testLooksLikeCalendarDate() {
        XCTAssertTrue(HeuristicNamer.looksLikeCalendarDate("March 3, 2024"))
        XCTAssertTrue(HeuristicNamer.looksLikeCalendarDate("12/04/2023"))
        XCTAssertTrue(HeuristicNamer.looksLikeCalendarDate("3/5"))
        XCTAssertFalse(HeuristicNamer.looksLikeCalendarDate("11:00 AM"))
        XCTAssertFalse(HeuristicNamer.looksLikeCalendarDate("noon"))
    }

    func testFirstGoodLineSkipsBoilerplate() {
        let text = """
        Page 1
        www.example.com
        info@example.com
        12/04/2023
        Annual Financial Review
        body text continues here
        """
        XCTAssertEqual(HeuristicNamer.firstGoodLine(in: text), "Annual Financial Review")
    }

    func testIsReasonableTitle() {
        XCTAssertTrue(HeuristicNamer.isReasonableTitle("Employment Agreement 2025"))
        XCTAssertFalse(HeuristicNamer.isReasonableTitle("Untitled"))
        XCTAssertFalse(HeuristicNamer.isReasonableTitle("a1"))
        XCTAssertFalse(HeuristicNamer.isReasonableTitle("12/04/2023 44:12"))
    }

    func testComposeTransactionalDocumentUsesOrgKindAndDate() {
        var analysis = HeuristicNamer.Analysis()
        analysis.title = "Thank You For Your Business"
        analysis.kind = HeuristicNamer.DocumentKind(label: "Invoice", isStrong: true)
        analysis.organization = "Acme"
        analysis.date = HeuristicNamer.isoDayFormatter.date(from: "2024-03-03").map {
            HeuristicNamer.DetectedDate(date: $0, timeZone: nil)
        }

        let extraction = PDFExtraction(
            fileName: "scan_0042",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            usedOCR: false
        )
        let (base, isWeak) = HeuristicNamer.compose(analysis, extraction: extraction, prefs: Preferences())
        XCTAssertEqual(base, "2024-03-03 Acme Invoice")
        XCTAssertFalse(isWeak)
    }

    func testComposeResumeGetsNoDatePrefix() {
        // Date prefixes are for transactional documents; a resume's first
        // detected date is usually incidental (graduation year etc.).
        var analysis = HeuristicNamer.Analysis()
        analysis.kind = HeuristicNamer.DocumentKind(label: "Resume", isStrong: false)
        analysis.person = "Jane Doe"
        analysis.date = HeuristicNamer.isoDayFormatter.date(from: "2019-05-15").map {
            HeuristicNamer.DetectedDate(date: $0, timeZone: nil)
        }

        let extraction = PDFExtraction(
            fileName: "resume_final",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            usedOCR: false
        )
        let (base, _) = HeuristicNamer.compose(analysis, extraction: extraction, prefs: Preferences())
        XCTAssertEqual(base, "Jane Doe Resume")
    }

    func testComposeFallsBackToOriginalFileName() {
        let extraction = PDFExtraction(
            fileName: "mystery",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            usedOCR: false
        )
        let (base, isWeak) = HeuristicNamer.compose(HeuristicNamer.Analysis(), extraction: extraction, prefs: Preferences())
        XCTAssertEqual(base, "mystery")
        XCTAssertTrue(isWeak)
    }

    func testSuggestNeverProducesAnUnusableName() {
        // A file whose raw name sanitizes to nothing must still get a
        // suggestion that survives sanitizing (otherwise it can't be applied).
        let extraction = PDFExtraction(
            fileName: "____",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            usedOCR: false
        )
        let (base, _) = HeuristicNamer.suggest(from: extraction, prefs: Preferences())
        XCTAssertFalse(FilenameSanitizer.sanitize(base).isEmpty)
    }

    func testOrgKindNameAvoidsDuplication() {
        XCTAssertEqual(HeuristicNamer.orgKindName(org: "Acme Invoice Services", kindLabel: "Invoice"), "Acme Invoice Services")
        XCTAssertEqual(HeuristicNamer.orgKindName(org: "Acme", kindLabel: "Invoice"), "Acme Invoice")
    }

    func testTruncateWords() {
        XCTAssertEqual(HeuristicNamer.truncateWords("one two three four", maxWords: 2), "one two")
        XCTAssertEqual(HeuristicNamer.truncateWords("short", maxWords: 10), "short")
    }
}
