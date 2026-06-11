import XCTest
@testable import Linkup

/// Unit tests for pure model logic and the backend endpoint builder.
final class LinkupModelTests: XCTestCase {

    // MARK: ShareSession

    func testShareSessionExpiry() {
        let expired = ShareSession(
            id: UUID(), startedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-1), eventName: "Past", hiddenFromConnectionIDs: []
        )
        XCTAssertTrue(expired.isExpired)

        let live = ShareSession(
            id: UUID(), startedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600), eventName: "Now", hiddenFromConnectionIDs: []
        )
        XCTAssertFalse(live.isExpired)
        XCTAssertTrue(live.remainingLabel.contains("left"))
    }

    // MARK: String.initials

    func testInitials() {
        XCTAssertEqual("Josh Greco".initials, "JG")
        XCTAssertEqual("madonna".initials, "M")
        XCTAssertEqual("Ada B. Lovelace".initials, "AB")
        XCTAssertEqual("".initials, "")
    }

    // MARK: LinkedInNetworkConnection backward-compatible decoding

    func testConnectionDecodesWithMinimalLegacyJSON() throws {
        // An older persisted payload missing connectionProfileID, fieldMask,
        // verificationState, confidenceScore must still decode via the custom init.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "accountID": "\(UUID().uuidString)",
            "firstName": "Ada",
            "lastName": "Lovelace",
            "profileURL": "https://www.linkedin.com/in/ada",
            "importedAt": 738000000.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LinkedInNetworkConnection.self, from: json)
        XCTAssertEqual(decoded.firstName, "Ada")
        // connectionProfileID falls back to lowercased profile URL when absent.
        XCTAssertEqual(decoded.connectionProfileID, "https://www.linkedin.com/in/ada")
        XCTAssertEqual(decoded.verificationState, .imported)
        XCTAssertEqual(decoded.confidenceScore, 0.65, accuracy: 0.0001)
        XCTAssertTrue(decoded.fieldMask.hasFirstName)
    }

    // MARK: LinkupBackendService.endpoint

    func testEndpointPreservesFunctionBasePath() throws {
        let base = URL(string: "https://abc.supabase.co/functions/v1/linkedin-oauth")!
        let url = LinkupBackendService.endpoint(path: "linkedin/archive/sync", baseURL: base)
        XCTAssertEqual(url?.absoluteString,
                       "https://abc.supabase.co/functions/v1/linkedin-oauth/linkedin/archive/sync")
    }

    func testEndpointWithRootBaseURL() throws {
        let base = URL(string: "http://127.0.0.1:8000")!
        let url = LinkupBackendService.endpoint(path: "linkedin/archive/sync", baseURL: base)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:8000/linkedin/archive/sync")
    }

    func testUsableBaseURLRejectsPlaceholderAndEmpty() {
        // Placeholder / empty values must be treated as "not configured" so the
        // sync call cleanly no-ops until the deployed function URL is filled in.
        XCTAssertNil(LinkupBackendService.usableBaseURL(from: "####### ENTER SUPABASE EDGE FUNCTION BASE URL HERE #######"))
        XCTAssertNil(LinkupBackendService.usableBaseURL(from: "  "))
        XCTAssertNil(LinkupBackendService.usableBaseURL(from: nil))
        XCTAssertNil(LinkupBackendService.usableBaseURL(from: "REPLACE_WITH_URL"))
    }

    func testUsableBaseURLAcceptsRealURL() {
        XCTAssertEqual(
            LinkupBackendService.usableBaseURL(from: "https://abc.supabase.co/functions/v1/linkedin-oauth")?.absoluteString,
            "https://abc.supabase.co/functions/v1/linkedin-oauth"
        )
    }
}
