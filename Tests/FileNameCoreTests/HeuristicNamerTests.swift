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

    func testDetectDatePrefersLabeledDate() {
        let text = """
        Some Corp
        Payment due within 30 days of December 31, 2030.
        Invoice Date: March 3, 2024
        """
        let date = HeuristicNamer.detectDate(in: text)
        XCTAssertNotNil(date)
        if let date {
            XCTAssertEqual(HeuristicNamer.isoDayFormatter.string(from: date), "2024-03-03")
        }
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
        analysis.date = HeuristicNamer.isoDayFormatter.date(from: "2024-03-03")

        let extraction = PDFExtraction(
            fileName: "scan_0042",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            pageCount: 1,
            usedOCR: false
        )
        let (base, isWeak) = HeuristicNamer.compose(analysis, extraction: extraction, prefs: Preferences())
        XCTAssertEqual(base, "2024-03-03 Acme Invoice")
        XCTAssertFalse(isWeak)
    }

    func testComposeFallsBackToOriginalFileName() {
        let extraction = PDFExtraction(
            fileName: "mystery",
            metadataTitle: nil,
            fontTitle: nil,
            text: "",
            pageCount: 1,
            usedOCR: false
        )
        let (base, isWeak) = HeuristicNamer.compose(HeuristicNamer.Analysis(), extraction: extraction, prefs: Preferences())
        XCTAssertEqual(base, "mystery")
        XCTAssertTrue(isWeak)
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
