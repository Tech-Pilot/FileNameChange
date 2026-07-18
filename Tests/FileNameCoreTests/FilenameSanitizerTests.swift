import XCTest
@testable import FileNameCore

final class FilenameSanitizerTests: XCTestCase {

    func testRemovesIllegalCharacters() {
        let result = FilenameSanitizer.sanitize("Q3/Q4: Sales <Draft>?*|\"Report\"")
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains(":"))
        XCTAssertFalse(result.contains("<"))
        XCTAssertFalse(result.contains(">"))
        XCTAssertFalse(result.contains("?"))
        XCTAssertFalse(result.contains("*"))
        XCTAssertFalse(result.contains("|"))
        XCTAssertFalse(result.contains("\""))
        XCTAssertTrue(result.contains("Q3-Q4"))
        XCTAssertTrue(result.contains("Report"))
    }

    func testCapsLengthAtWordBoundary() {
        let longInput = Array(repeating: "wordy", count: 60).joined(separator: " ")
        let result = FilenameSanitizer.sanitize(longInput)
        XCTAssertLessThanOrEqual(result.count, FilenameSanitizer.maxLength)
        XCTAssertFalse(result.hasSuffix(" "))
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.hasSuffix("wordy"), "should cut at a word boundary, not mid-word")
    }

    func testCapsLengthAtWordBoundaryWithHyphenSeparators() {
        // Hyphen-separated names (the user's separator preference) must also
        // truncate at a boundary, not mid-word.
        let longInput = Array(repeating: "wordy", count: 60).joined(separator: "-")
        let result = FilenameSanitizer.sanitize(longInput)
        XCTAssertLessThanOrEqual(result.count, FilenameSanitizer.maxLength)
        XCTAssertTrue(result.hasSuffix("wordy"), "should cut at a hyphen boundary, not mid-word")
        XCTAssertFalse(result.hasSuffix("-"))
    }

    func testStripsLeadingDotsAndTrailingJunk() {
        XCTAssertEqual(FilenameSanitizer.sanitize("...hidden name. "), "hidden name")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(FilenameSanitizer.sanitize("   "), "")
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(FilenameSanitizer.sanitize("Annual   Report\n2024"), "Annual Report 2024")
    }

    func testReservedWindowsNamesGetSuffix() {
        XCTAssertEqual(FilenameSanitizer.sanitize("CON"), "CON File")
        XCTAssertEqual(FilenameSanitizer.sanitize("com1"), "com1 File")
        XCTAssertEqual(FilenameSanitizer.sanitize("Nul"), "Nul File")
        // Normal names that merely contain a reserved word are untouched.
        XCTAssertEqual(FilenameSanitizer.sanitize("Concert Tickets"), "Concert Tickets")
    }

    func testKeepsZeroWidthJoiners() {
        // ZWJ/ZWNJ are legal in file names; stripping them corrupts emoji
        // sequences and Persian/Arabic orthography.
        let family = "Family \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Photos"
        XCTAssertTrue(FilenameSanitizer.sanitize(family).contains("\u{200D}"))
    }

    func testStripsBidiControlCharacters() {
        let spoofed = "Report\u{202E}fdp.exe"
        XCTAssertFalse(FilenameSanitizer.sanitize(spoofed).contains("\u{202E}"))
    }

    func testStrippingPDFExtension() {
        XCTAssertEqual(FilenameSanitizer.strippingPDFExtension("Report.pdf"), "Report")
        XCTAssertEqual(FilenameSanitizer.strippingPDFExtension("Report.PDF"), "Report")
        XCTAssertEqual(FilenameSanitizer.strippingPDFExtension("Report"), "Report")
        XCTAssertEqual(FilenameSanitizer.strippingPDFExtension("Report.pdf.pdf"), "Report.pdf")
    }

    func testTitleCaseKeepsAcronymsAndSmallWords() {
        let result = FilenameSanitizer.titleCased("the quick BROWN fox of doom")
        XCTAssertEqual(result, "The Quick BROWN Fox of Doom")
    }

    func testApplyStyleHyphens() {
        let result = FilenameSanitizer.applyStyle(to: "Acme Invoice 2024", caseStyle: .lowercase, separator: .hyphens)
        XCTAssertEqual(result, "acme-invoice-2024")
    }

    func testCleanAISuggestionStripsQuotesPrefixesAndExtension() {
        XCTAssertEqual(
            FilenameSanitizer.cleanAISuggestion("\"2024-01-05 Acme Invoice.pdf\""),
            "2024-01-05 Acme Invoice"
        )
        XCTAssertEqual(
            FilenameSanitizer.cleanAISuggestion("Filename: Board Meeting Minutes"),
            "Board Meeting Minutes"
        )
        XCTAssertEqual(
            FilenameSanitizer.cleanAISuggestion("Rental Agreement\nExtra explanation line"),
            "Rental Agreement"
        )
    }

    func testCandidateNames() {
        XCTAssertEqual(FilenameSanitizer.candidateNames(base: "Report", attempt: 1), "Report")
        XCTAssertEqual(FilenameSanitizer.candidateNames(base: "Report", attempt: 3), "Report 3")
    }

    func testAvailableURLSkipsExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameChangeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let taken = directory.appendingPathComponent("Invoice.pdf")
        try Data("x".utf8).write(to: taken)

        let available = try FilenameSanitizer.availableURL(in: directory, base: "Invoice", pathExtension: "pdf")
        XCTAssertEqual(available.lastPathComponent, "Invoice 2.pdf")
    }

    func testAvailableURLAllowsCaseOnlyRename() throws {
        // Changing only capitalization must not trip the collision check on
        // case-insensitive file systems and produce "Name 2.pdf".
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameChangeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("invoice scan.pdf")
        try Data("x".utf8).write(to: source)

        let destination = try FilenameSanitizer.availableURL(
            in: directory,
            base: "Invoice Scan",
            pathExtension: "pdf",
            movingFrom: source
        )
        XCTAssertEqual(destination.lastPathComponent, "Invoice Scan.pdf")
    }
}
