import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum LinkedInAPIImportError: LocalizedError {
    case missingClientID
    case missingRedirectURI
    case missingCallbackScheme
    case missingAPIBaseURL
    case invalidAuthorizationURL
    case callbackMissingCode
    case stateMismatch
    case backendError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add your LinkedIn client id in Info.plist."
        case .missingRedirectURI:
            return "Add your LinkedIn redirect URI in Info.plist."
        case .missingCallbackScheme:
            return "Add your LinkedIn callback URL scheme in Info.plist."
        case .missingAPIBaseURL:
            return "Add your Linkup API base URL in Info.plist."
        case .invalidAuthorizationURL:
            return "LinkedIn authorization could not be started."
        case .callbackMissingCode:
            return "LinkedIn did not return an authorization code."
        case .stateMismatch:
            return "LinkedIn authorization state did not match."
        case .backendError(let message):
            return message
        }
    }
}

struct LinkedInAPIMember: Codable, Equatable {
    var subject: String
    var name: String?
    var givenName: String?
    var familyName: String?
    var email: String?
    // OpenID Connect `picture` claim threaded through by the Edge Function.
    // Used by Settings + ProfileSheet to render a real avatar instead of
    // initials. Backwards-compatible decoding — older payloads omit it.
    var picture: URL?
    var profileURL: String?
    var profileSlug: String?
    var verifiedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case subject, name, givenName, familyName, email, picture, profileURL, profileSlug, verifiedAt
    }

    init(
        subject: String,
        name: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        email: String? = nil,
        picture: URL? = nil,
        profileURL: String? = nil,
        profileSlug: String? = nil,
        verifiedAt: Date? = nil
    ) {
        self.subject = subject
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.picture = picture
        self.profileURL = profileURL
        self.profileSlug = profileSlug
        self.verifiedAt = verifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subject = try container.decode(String.self, forKey: .subject)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        if let raw = try container.decodeIfPresent(String.self, forKey: .picture), !raw.isEmpty {
            picture = URL(string: raw)
        } else {
            picture = nil
        }
        profileURL = try container.decodeIfPresent(String.self, forKey: .profileURL)
        profileSlug = try container.decodeIfPresent(String.self, forKey: .profileSlug)
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
    }
}

struct LinkedInAPIImportPayload: Codable, Equatable {
    var member: LinkedInAPIMember
    var importRecord: LinkedInImportRecord
    var profiles: [LinkedInProfileRecord]
    var connections: [LinkedInNetworkConnection]
    var profileObservations: [LinkedInProfileObservation]
}

private struct LinkedInOAuthConfiguration {
    let clientID: String
    let redirectURI: String
    let callbackScheme: String
    let apiBaseURL: URL
    // Scopes intentionally exclude `r_1st_connections`: connection data is sourced
    // from the user's LinkedIn data export (CSV archive), not the LinkedIn API.
    let scopes = "openid profile email"

    static func load() throws -> LinkedInOAuthConfiguration {
        let bundle = Bundle.main
        let clientID = try requiredInfoValue("LINKEDIN_CLIENT_ID", in: bundle, missing: .missingClientID)
        let redirectURI = try requiredInfoValue("LINKEDIN_REDIRECT_URI", in: bundle, missing: .missingRedirectURI)
        let callbackScheme = try requiredInfoValue("LINKEDIN_OAUTH_CALLBACK_SCHEME", in: bundle, missing: .missingCallbackScheme)
        let apiBase = try requiredInfoValue("LINKUP_API_BASE_URL", in: bundle, missing: .missingAPIBaseURL)
        guard let apiBaseURL = URL(string: apiBase) else { throw LinkedInAPIImportError.missingAPIBaseURL }
        return LinkedInOAuthConfiguration(
            clientID: clientID,
            redirectURI: redirectURI,
            callbackScheme: callbackScheme,
            apiBaseURL: apiBaseURL
        )
    }

    private static func requiredInfoValue(_ key: String, in bundle: Bundle, missing: LinkedInAPIImportError) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("REPLACE_WITH"),
              !value.contains("#######") else {
            throw missing
        }
        return value
    }
}

@MainActor
final class LinkedInAPIImportService: NSObject {
    private var webSession: ASWebAuthenticationSession?

    func importConnections(accountID: UUID) async throws -> LinkedInAPIImportPayload {
        let configuration = try LinkedInOAuthConfiguration.load()
        let state = randomURLSafeString()
        let codeVerifier = randomURLSafeString()
        let codeChallenge = pkceChallenge(for: codeVerifier)
        let authorizationURL = try makeAuthorizationURL(
            configuration: configuration,
            state: state,
            codeChallenge: codeChallenge
        )
        let callbackURL = try await requestAuthorizationCode(
            authorizationURL: authorizationURL,
            callbackScheme: configuration.callbackScheme
        )
        let code = try authorizationCode(from: callbackURL, expectedState: state)
        return try await exchangeCodeForConnections(
            accountID: accountID,
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: configuration.redirectURI,
            apiBaseURL: configuration.apiBaseURL
        )
    }

    private func makeAuthorizationURL(configuration: LinkedInOAuthConfiguration, state: String, codeChallenge: String) throws -> URL {
        var components = URLComponents(string: "https://www.linkedin.com/oauth/v2/authorization")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: configuration.scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw LinkedInAPIImportError.invalidAuthorizationURL }
        return url
    }

    private func requestAuthorizationCode(authorizationURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            webSession = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: LinkedInAPIImportError.callbackMissingCode)
                    }
                    self.webSession = nil
                }
            }
            webSession?.presentationContextProvider = self
            webSession?.prefersEphemeralWebBrowserSession = false
            webSession?.start()
        }
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        if let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value {
            throw LinkedInAPIImportError.backendError(errorDescription)
        }
        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else { throw LinkedInAPIImportError.stateMismatch }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw LinkedInAPIImportError.callbackMissingCode
        }
        return code
    }

    private func exchangeCodeForConnections(accountID: UUID, code: String, codeVerifier: String, redirectURI: String, apiBaseURL: URL) async throws -> LinkedInAPIImportPayload {
        guard let endpoint = backendURL(path: "linkedin/oauth/exchange", baseURL: apiBaseURL) else {
            throw LinkedInAPIImportError.missingAPIBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode([
            "accountID": accountID.uuidString,
            "code": code,
            "redirectURI": redirectURI,
            "codeVerifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        if !(200..<300).contains(status) {
            let backendMessage = (try? JSONDecoder().decode(LinkedInBackendError.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw LinkedInAPIImportError.backendError(backendMessage)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LinkedInAPIImportPayload.self, from: data)
    }

    private func backendURL(path: String, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let combinedPath = ([basePath, path].filter { !$0.isEmpty }).joined(separator: "/")
        components?.path = "/\(combinedPath)"
        return components?.url
    }

    private func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// RFC 7636 S256 PKCE challenge: BASE64URL(SHA256(code_verifier)).
    private func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension LinkedInAPIImportService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

private struct LinkedInBackendError: Decodable {
    var error: String
}
