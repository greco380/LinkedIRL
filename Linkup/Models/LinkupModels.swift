import CoreLocation
import Foundation
import SwiftUI

enum AuthMethod: String, Codable, CaseIterable {
    case email, apple, google, linkedin
}

enum ThemeChoice: String, Codable, CaseIterable {
    case light, dark
}

enum Audience: String, Codable, CaseIterable {
    case firstDegree
    case firstAndSecondDegree

    var title: String {
        switch self {
        case .firstDegree: "1st"
        case .firstAndSecondDegree: "1st + 2nd"
        }
    }
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var email: String
    var authMethod: AuthMethod
    var appleSubject: String?
    var googleSubject: String?
    var linkedInConnected: Bool
    var linkedInURL: String?
    var linkedInMemberID: String? = nil
    var linkedInProfileSlug: String? = nil
    var linkedInPictureURL: URL? = nil
    var linkedInVerifiedAt: Date? = nil
    var linkedInImportedAt: Date?
    var linkedInConnectionCount: Int
    var pushToken: String?
    var createdAt: Date
    var lastSignedInAt: Date

    var initials: String {
        displayName.initials
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, email, authMethod, appleSubject, googleSubject
        case linkedInConnected, linkedInURL, linkedInMemberID, linkedInProfileSlug
        case linkedInPictureURL, linkedInVerifiedAt, linkedInImportedAt
        case linkedInConnectionCount, pushToken, createdAt, lastSignedInAt
    }

    init(
        id: UUID,
        displayName: String,
        email: String,
        authMethod: AuthMethod,
        appleSubject: String?,
        googleSubject: String?,
        linkedInConnected: Bool,
        linkedInURL: String?,
        linkedInMemberID: String? = nil,
        linkedInProfileSlug: String? = nil,
        linkedInPictureURL: URL? = nil,
        linkedInVerifiedAt: Date? = nil,
        linkedInImportedAt: Date?,
        linkedInConnectionCount: Int,
        pushToken: String?,
        createdAt: Date,
        lastSignedInAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.authMethod = authMethod
        self.appleSubject = appleSubject
        self.googleSubject = googleSubject
        self.linkedInConnected = linkedInConnected
        self.linkedInURL = linkedInURL
        self.linkedInMemberID = linkedInMemberID
        self.linkedInProfileSlug = linkedInProfileSlug
        self.linkedInPictureURL = linkedInPictureURL
        self.linkedInVerifiedAt = linkedInVerifiedAt
        self.linkedInImportedAt = linkedInImportedAt
        self.linkedInConnectionCount = linkedInConnectionCount
        self.pushToken = pushToken
        self.createdAt = createdAt
        self.lastSignedInAt = lastSignedInAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decode(String.self, forKey: .email)
        authMethod = try container.decode(AuthMethod.self, forKey: .authMethod)
        appleSubject = try container.decodeIfPresent(String.self, forKey: .appleSubject)
        googleSubject = try container.decodeIfPresent(String.self, forKey: .googleSubject)
        linkedInConnected = try container.decode(Bool.self, forKey: .linkedInConnected)
        linkedInURL = try container.decodeIfPresent(String.self, forKey: .linkedInURL)
        linkedInMemberID = try container.decodeIfPresent(String.self, forKey: .linkedInMemberID)
        linkedInProfileSlug = try container.decodeIfPresent(String.self, forKey: .linkedInProfileSlug)
        linkedInPictureURL = try container.decodeIfPresent(URL.self, forKey: .linkedInPictureURL)
        linkedInVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .linkedInVerifiedAt)
        linkedInImportedAt = try container.decodeIfPresent(Date.self, forKey: .linkedInImportedAt)
        linkedInConnectionCount = try container.decodeIfPresent(Int.self, forKey: .linkedInConnectionCount) ?? 0
        pushToken = try container.decodeIfPresent(String.self, forKey: .pushToken)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastSignedInAt = try container.decode(Date.self, forKey: .lastSignedInAt)
    }
}

struct AuthenticatedAccount: Codable, Equatable {
    var account: Account
    var sessionToken: String
}

struct UserSettings: Codable, Equatable {
    var theme: ThemeChoice
    var defaultShareHours: Int
    var audience: Audience
    var autoShareKnownEvents: Bool
    var notifNewSharer: Bool
    var notifNewMessage: Bool
    var notifExpiring: Bool

    static let defaults = UserSettings(
        theme: .light,
        defaultShareHours: 2,
        audience: .firstDegree,
        autoShareKnownEvents: false,
        notifNewSharer: true,
        notifNewMessage: true,
        notifExpiring: true
    )
}

struct SharedEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var dateLabel: String
}

struct ConnectionProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var headline: String
    var initials: String
    var colorHex: String
    var connectedAtLabel: String
    var yearsExperience: Int
    var yearsAtCurrentCompany: Int
    var bio: String
    var sharedEvents: [SharedEvent]
    var mapX: Double
    var mapY: Double

    var connectedYear: String {
        connectedAtLabel.split(separator: " ").last.map(String.init) ?? connectedAtLabel
    }

    var currentCompany: String {
        headline.components(separatedBy: " at ").last ?? "current role"
    }
}

enum LinkedInImportSource: String, Codable, CaseIterable {
    case csvExport = "csv_export"
    case linkedinArchive = "linkedin_archive"
    case linkedinAPI = "linkedin_api"
    case portabilityAPI = "portability_api"
}

enum LinkedInConnectionVerificationState: String, Codable, CaseIterable {
    case imported
    case reciprocal
    case selfVerified = "self_verified"
}

struct LinkedInConnectionFieldMask: Codable, Equatable {
    var hasFirstName: Bool
    var hasLastName: Bool
    var hasCompany: Bool
    var hasPosition: Bool
    var hasEmailHash: Bool
    var hasConnectedOn: Bool
}

struct LinkedInImportRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var accountID: UUID
    var source: LinkedInImportSource
    var importedAt: Date
    var rowCount: Int
    var fileHash: String
}

struct LinkedInProfileObservation: Codable, Identifiable, Equatable {
    let id: UUID
    var profileID: String
    var importID: UUID
    var source: LinkedInImportSource
    var observedAt: Date
    var firstName: String?
    var lastName: String?
    var company: String?
    var position: String?
    var rawURL: String
    var rawRowHash: String
}

struct LinkedInProfileRecord: Codable, Identifiable, Equatable {
    var id: String
    var normalizedURL: String
    var slug: String?
    var firstName: String?
    var lastName: String?
    var company: String?
    var position: String?
}

struct LinkedInNetworkConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let accountID: UUID
    var connectionProfileID: String
    var importID: UUID?
    var verificationState: LinkedInConnectionVerificationState
    var confidenceScore: Double
    var fieldMask: LinkedInConnectionFieldMask
    var firstName: String
    var lastName: String
    var profileURL: String
    var emailHash: String?
    var company: String?
    var position: String?
    var connectedOn: Date?
    var importedAt: Date

    init(
        id: UUID,
        accountID: UUID,
        connectionProfileID: String,
        importID: UUID?,
        verificationState: LinkedInConnectionVerificationState = .imported,
        confidenceScore: Double,
        fieldMask: LinkedInConnectionFieldMask,
        firstName: String,
        lastName: String,
        profileURL: String,
        emailHash: String?,
        company: String?,
        position: String?,
        connectedOn: Date?,
        importedAt: Date
    ) {
        self.id = id
        self.accountID = accountID
        self.connectionProfileID = connectionProfileID
        self.importID = importID
        self.verificationState = verificationState
        self.confidenceScore = confidenceScore
        self.fieldMask = fieldMask
        self.firstName = firstName
        self.lastName = lastName
        self.profileURL = profileURL
        self.emailHash = emailHash
        self.company = company
        self.position = position
        self.connectedOn = connectedOn
        self.importedAt = importedAt
    }

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountID
        case connectionProfileID
        case importID
        case verificationState
        case confidenceScore
        case fieldMask
        case firstName
        case lastName
        case profileURL
        case emailHash
        case company
        case position
        case connectedOn
        case importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProfileURL = try container.decode(String.self, forKey: .profileURL)
        let decodedFirstName = try container.decode(String.self, forKey: .firstName)
        let decodedLastName = try container.decode(String.self, forKey: .lastName)
        let decodedCompany = try container.decodeIfPresent(String.self, forKey: .company)
        let decodedPosition = try container.decodeIfPresent(String.self, forKey: .position)
        let decodedConnectedOn = try container.decodeIfPresent(Date.self, forKey: .connectedOn)
        let decodedEmailHash = try container.decodeIfPresent(String.self, forKey: .emailHash)

        id = try container.decode(UUID.self, forKey: .id)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        connectionProfileID = try container.decodeIfPresent(String.self, forKey: .connectionProfileID) ?? decodedProfileURL.lowercased()
        importID = try container.decodeIfPresent(UUID.self, forKey: .importID)
        verificationState = try container.decodeIfPresent(LinkedInConnectionVerificationState.self, forKey: .verificationState) ?? .imported
        confidenceScore = try container.decodeIfPresent(Double.self, forKey: .confidenceScore) ?? 0.65
        fieldMask = try container.decodeIfPresent(LinkedInConnectionFieldMask.self, forKey: .fieldMask) ?? LinkedInConnectionFieldMask(
            hasFirstName: !decodedFirstName.isEmpty,
            hasLastName: !decodedLastName.isEmpty,
            hasCompany: decodedCompany != nil,
            hasPosition: decodedPosition != nil,
            hasEmailHash: decodedEmailHash != nil,
            hasConnectedOn: decodedConnectedOn != nil
        )
        firstName = decodedFirstName
        lastName = decodedLastName
        profileURL = decodedProfileURL
        emailHash = decodedEmailHash
        company = decodedCompany
        position = decodedPosition
        connectedOn = decodedConnectedOn
        importedAt = try container.decode(Date.self, forKey: .importedAt)
    }
}

struct LinkedInNetworkDatabase: Codable, Equatable {
    var accountID: UUID
    var profileURL: String
    var profiles: [LinkedInProfileRecord]
    var connections: [LinkedInNetworkConnection]
    var imports: [LinkedInImportRecord]
    var profileObservations: [LinkedInProfileObservation]
    var importedAt: Date

    init(
        accountID: UUID,
        profileURL: String,
        profiles: [LinkedInProfileRecord] = [],
        connections: [LinkedInNetworkConnection],
        importedAt: Date,
        imports: [LinkedInImportRecord] = [],
        profileObservations: [LinkedInProfileObservation] = []
    ) {
        self.accountID = accountID
        self.profileURL = profileURL
        self.profiles = profiles
        self.connections = connections
        self.imports = imports
        self.profileObservations = profileObservations
        self.importedAt = importedAt
    }

    private enum CodingKeys: String, CodingKey {
        case accountID
        case profileURL
        case profiles
        case connections
        case imports
        case profileObservations
        case importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        profileURL = try container.decode(String.self, forKey: .profileURL)
        profiles = try container.decodeIfPresent([LinkedInProfileRecord].self, forKey: .profiles) ?? []
        connections = try container.decode([LinkedInNetworkConnection].self, forKey: .connections)
        imports = try container.decodeIfPresent([LinkedInImportRecord].self, forKey: .imports) ?? []
        profileObservations = try container.decodeIfPresent([LinkedInProfileObservation].self, forKey: .profileObservations) ?? []
        importedAt = try container.decode(Date.self, forKey: .importedAt)
    }

    var count: Int {
        connections.count
    }
}

struct ShareSession: Codable, Identifiable, Equatable {
    let id: UUID
    var startedAt: Date
    var expiresAt: Date
    var eventName: String
    var hiddenFromConnectionIDs: Set<String>

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var remainingLabel: String {
        let remaining = max(0, Int(expiresAt.timeIntervalSince(Date())))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Sender: String, Codable {
        case me, them
    }

    /// Delivery status for a single chat bubble. `sending` is shown immediately
    /// after the user taps send (optimistic UI); `sent` means the backend
    /// accepted the row; `failed` lets the user retry. Older serialized
    /// messages without this field decode as `.sent` for backward compatibility.
    enum SendStatus: String, Codable {
        case sending
        case sent
        case failed
    }

    let id: UUID
    var connectionID: String
    var sender: Sender
    var body: String
    var sentAt: Date
    var status: SendStatus = .sent

    private enum CodingKeys: String, CodingKey {
        case id, connectionID, sender, body, sentAt, status
    }

    init(
        id: UUID,
        connectionID: String,
        sender: Sender,
        body: String,
        sentAt: Date,
        status: SendStatus = .sent
    ) {
        self.id = id
        self.connectionID = connectionID
        self.sender = sender
        self.body = body
        self.sentAt = sentAt
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        connectionID = try container.decode(String.self, forKey: .connectionID)
        sender = try container.decode(Sender.self, forKey: .sender)
        body = try container.decode(String.self, forKey: .body)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        status = try container.decodeIfPresent(SendStatus.self, forKey: .status) ?? .sent
    }
}

extension String {
    var initials: String {
        let parts = split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map(String.init).joined().uppercased()
    }
}
