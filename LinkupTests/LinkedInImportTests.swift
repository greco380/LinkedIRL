import XCTest
@testable import Linkup

/// Exercises the real LinkedInNetworkImportService against on-disk CSV fixtures,
/// including the edge cases hardened in this pass (UTF-8 BOM, quoted commas,
/// the LinkedIn "Notes:" preamble, alternate encodings, and bad input).
final class LinkedInImportTests: XCTestCase {
    private let service = LinkedInNetworkImportService()
    private let accountID = UUID()

    private let header = "First Name,Last Name,URL,Email Address,Company,Position,Connected On"
    private let preamble = """
    Notes:
    "Some LinkedIn export preamble line that must be skipped before the header."

    """

    private func writeTempFile(_ text: String, encoding: String.Encoding = .utf8, addBOM: Bool = false) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        var data = Data()
        if addBOM { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        data.append(text.data(using: encoding)!)
        try data.write(to: url)
        return url
    }

    private func sampleBody() -> String {
        """
        \(preamble)\(header)
        Sample,One,https://www.linkedin.com/in/sample-one,,Example Co,Engineer,25 May 2026
        Sample,Two,https://www.linkedin.com/in/sample-two,sample2@example.com,Example Co,Designer,18 Apr 2026
        Sample,Four,https://www.linkedin.com/in/sample-four,,Other Co,"Manager, Things",11 Apr 2026
        """
    }

    func testParsesStandardExport() throws {
        let url = try writeTempFile(sampleBody())
        let result = try service.importConnections(from: url, accountID: accountID, source: .linkedinArchive)
        XCTAssertEqual(result.connections.count, 3)
        XCTAssertEqual(result.importRecord.rowCount, 3)
        // Quoted field containing a comma must be preserved as one column.
        let four = result.connections.first { $0.profileURL.contains("sample-four") }
        XCTAssertEqual(four?.position, "Manager, Things")
    }

    func testParsesFileWithUTF8BOM() throws {
        // Before the fix, a BOM made the first header cell "\u{FEFF}First Name",
        // so header detection failed and the import threw .missingHeader.
        let url = try writeTempFile(sampleBody(), addBOM: true)
        let result = try service.importConnections(from: url, accountID: accountID, source: .linkedinArchive)
        XCTAssertEqual(result.connections.count, 3)
    }

    func testParsesWindowsCP1252Encoding() throws {
        let body = "\(preamble)\(header)\nJosé,Núñez,https://www.linkedin.com/in/jose-nunez,,Café Co,Chef,11 Apr 2026"
        let url = try writeTempFile(body, encoding: .windowsCP1252)
        let result = try service.importConnections(from: url, accountID: accountID, source: .linkedinArchive)
        XCTAssertEqual(result.connections.count, 1)
        XCTAssertEqual(result.connections.first?.firstName, "José")
    }

    func testBuildsStableProfileIDAndSlug() throws {
        let url = try writeTempFile(sampleBody())
        let result = try service.importConnections(from: url, accountID: accountID, source: .linkedinArchive)
        let one = result.connections.first { $0.profileURL.contains("sample-one") }
        XCTAssertEqual(one?.connectionProfileID, "linkedin:in:sample-one")
    }

    func testThrowsMissingHeaderWhenNotAnExport() throws {
        let url = try writeTempFile("just,some,random\n1,2,3")
        XCTAssertThrowsError(try service.importConnections(from: url, accountID: accountID)) { error in
            XCTAssertEqual(error as? LinkedInImportError, .missingHeader)
        }
    }

    func testThrowsNoConnectionsWhenHeaderOnly() throws {
        let url = try writeTempFile("\(preamble)\(header)\n")
        XCTAssertThrowsError(try service.importConnections(from: url, accountID: accountID)) { error in
            XCTAssertEqual(error as? LinkedInImportError, .noConnections)
        }
    }

    func testZipIsRejectedWithGuidance() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        try Data([0x50, 0x4B]).write(to: url)
        XCTAssertThrowsError(try service.importConnections(from: url, accountID: accountID)) { error in
            XCTAssertEqual(error as? LinkedInImportError, .archiveExtractionUnavailable)
        }
    }

    func testNormalizedProfileURLRejectsNonLinkedIn() {
        XCTAssertThrowsError(try service.normalizedProfileURL("https://example.com/in/foo"))
        XCTAssertNoThrow(try service.normalizedProfileURL("linkedin.com/in/foo"))
    }

    func testEmailIsHashedNotStored() throws {
        let url = try writeTempFile(sampleBody())
        let result = try service.importConnections(from: url, accountID: accountID, source: .linkedinArchive)
        let two = result.connections.first { $0.profileURL.contains("sample-two") }
        // Raw email must never survive into the model.
        XCTAssertNotNil(two?.emailHash)
        XCTAssertEqual(two?.emailHash?.count, 64) // SHA-256 hex
        XCTAssertNotEqual(two?.emailHash, "sample2@example.com")
    }
}
