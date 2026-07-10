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
}
