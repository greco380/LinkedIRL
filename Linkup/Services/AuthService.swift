// AuthService.swift
// Authentication facade for Linkup. Routes to Supabase Auth when
// `LinkupSupabase.shared` is configured (live cross-device auth + RLS); falls
// back to the original UserDefaults credential store when it's not (demo mode
// + when the SPM package hasn't been linked yet). The fallback path lets the
// app keep working before Josh fills in SUPABASE_ANON_KEY and adds the SPM
// dependency in Xcode.
//
// MARK: - REQUIRES SPM (see SupabaseClient.swift for instructions)

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

#if canImport(Supabase)
import Supabase
import Auth
// `AnyJSON` lives in the Helpers module that ships alongside Auth. The umbrella
// `Supabase` import re-exports it; this explicit import keeps the symbol
// resolvable even on minor reorganisations of the SDK.
#if canImport(Helpers)
import Helpers
#endif
#endif

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case missingName
    case accountExists
    case accountNotFound
    case invalidPassword
    case appleCredentialMissing
    case googleNotConfigured
    case googleCallbackMissingToken
    case supabaseFailure(String)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .missingName:
            return "Enter your full name."
        case .accountExists:
            return "An account already exists for that email."
        case .accountNotFound:
            return "No account exists for those credentials."
        case .invalidPassword:
            return "The password is incorrect."
        case .appleCredentialMissing:
            return "Apple did not return enough account information."
        case .googleNotConfigured:
            return "Google Sign-In needs a Google OAuth client id in Info.plist."
        case .googleCallbackMissingToken:
            return "Google Sign-In did not return a usable token."
        case .supabaseFailure(let message):
            return message
        case .deletionFailed(let message):
            return message
        }
    }
}

struct EmailPasswordCredential: Codable, Equatable {
    var accountID: UUID
    var email: String
    var salt: String
    var passwordHash: String
}

struct SocialCredential: Codable, Equatable {
    var accountID: UUID
    var provider: AuthMethod
    var subject: String
    var email: String
}

@MainActor
final class AuthService: NSObject {
    private let defaults: UserDefaults
    private let keychain: KeychainSessionStore
    private var appleContinuation: CheckedContinuation<AuthenticatedAccount, Error>?
    private var webSession: ASWebAuthenticationSession?
    private var appleNonce: String?

    /// True when the Supabase SDK is linked AND the anon key is filled in. All
    /// the new code paths short-circuit on this; the legacy local-UserDefaults
    /// path runs otherwise.
    private var supabaseEnabled: Bool {
        LinkupSupabase.shared != nil
    }

    private enum Keys {
        static let accounts = "linkup.auth.accounts"
        static let emailCredentials = "linkup.auth.emailCredentials"
        static let socialCredentials = "linkup.auth.socialCredentials"
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainSessionStore = KeychainSessionStore()) {
        self.defaults = defaults
        self.keychain = keychain
        super.init()
    }

    // MARK: - Email / password

    func createEmailAccount(name: String, email: String, password: String) async throws -> AuthenticatedAccount {
        let normalizedEmail = try normalizeEmail(email)
        guard password.count >= 8 else { throw AuthError.weakPassword }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AuthError.missingName }

        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            do {
                let response = try await supabase.auth.signUp(
                    email: normalizedEmail,
                    password: password,
                    data: ["display_name": AnyJSON.string(trimmedName)]
                )
                let userID = response.user.id
                let account = makeAccount(
                    id: userID,
                    displayName: trimmedName,
                    email: normalizedEmail,
                    method: .email,
                    appleSubject: nil,
                    googleSubject: nil
                )
                return authenticated(account)
            } catch {
                throw AuthError.supabaseFailure(error.localizedDescription)
            }
        }
        #endif

        // Local fallback (kept so the app demos pre-SDK).
        var accounts = loadAccounts()
        var credentials = loadEmailCredentials()
        guard credentials[normalizedEmail] == nil else { throw AuthError.accountExists }

        let account = makeAccount(
            id: UUID(),
            displayName: trimmedName,
            email: normalizedEmail,
            method: .email,
            appleSubject: nil,
            googleSubject: nil
        )
        let salt = randomToken()
        credentials[normalizedEmail] = EmailPasswordCredential(
            accountID: account.id,
            email: normalizedEmail,
            salt: salt,
            passwordHash: passwordHash(password, salt: salt)
        )
        accounts[account.id.uuidString] = account
        saveAccounts(accounts)
        saveEmailCredentials(credentials)
        return authenticated(account)
    }

    func signInEmail(email: String, password: String) async throws -> AuthenticatedAccount {
        let normalizedEmail = try normalizeEmail(email)

        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            do {
                let session = try await supabase.auth.signIn(email: normalizedEmail, password: password)
                let user = session.user
                let displayName = (user.userMetadata["display_name"]?.stringValue)
                    ?? normalizedEmail.components(separatedBy: "@").first?.capitalized
                    ?? "Linkup user"
                var account = makeAccount(
                    id: user.id,
                    displayName: displayName,
                    email: normalizedEmail,
                    method: .email,
                    appleSubject: nil,
                    googleSubject: nil
                )
                account.lastSignedInAt = Date()
                return authenticated(account)
            } catch {
                throw AuthError.supabaseFailure(error.localizedDescription)
            }
        }
        #endif

        let credentials = loadEmailCredentials()
        guard let credential = credentials[normalizedEmail],
              var account = loadAccounts()[credential.accountID.uuidString] else {
            throw AuthError.accountNotFound
        }
        guard credential.passwordHash == passwordHash(password, salt: credential.salt) else {
            throw AuthError.invalidPassword
        }
        account.lastSignedInAt = Date()
        persistUpdatedAccount(account)
        return authenticated(account)
    }

    // MARK: - Apple

    func signInWithApple() async throws -> AuthenticatedAccount {
        let nonce = randomToken()
        appleNonce = nonce
        return try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256Hex(nonce)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Google

    func signInWithGoogle() async throws -> AuthenticatedAccount {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_OAUTH_CLIENT_ID") as? String,
              !clientID.isEmpty,
              !clientID.contains("REPLACE_WITH"),
              !clientID.contains("#######") else {
            throw AuthError.googleNotConfigured
        }
        let redirectScheme = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_OAUTH_REDIRECT_SCHEME") as? String ?? "com.googleusercontent.apps.linkup"
        let redirectURI = "\(redirectScheme):/oauth2redirect"
        let state = randomToken()
        let nonce = randomToken()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "id_token token"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authURL = components.url else { throw AuthError.googleNotConfigured }

        return try await withCheckedThrowingContinuation { continuation in
            webSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { [weak self] callbackURL, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL,
                          let fragment = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.fragment,
                          let idToken = Self.fragmentValue("id_token", in: fragment) else {
                        continuation.resume(throwing: AuthError.googleCallbackMissingToken)
                        return
                    }
                    let claims = Self.decodeJWTClaims(idToken)
                    if let returnedNonce = claims["nonce"] as? String, returnedNonce != nonce {
                        continuation.resume(throwing: AuthError.googleCallbackMissingToken)
                        return
                    }
                    let subject = claims["sub"] as? String ?? idToken
                    let email = claims["email"] as? String ?? "google-user@linkup.local"
                    let name = claims["name"] as? String ?? email.components(separatedBy: "@").first?.capitalized ?? "Google User"

                    do {
                        let result = try await self.completeSocialSignIn(
                            method: .google,
                            subject: subject,
                            name: name,
                            email: email,
                            idToken: idToken,
                            nonce: nonce
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            webSession?.presentationContextProvider = self
            webSession?.prefersEphemeralWebBrowserSession = true
            webSession?.start()
        }
    }

    // MARK: - Session

    func restoreSession() async -> Account? {
        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            do {
                let session = try await supabase.auth.session
                let user = session.user
                let snapshot = defaults.decode(Account.self, forKey: "linkup.account")
                if let snapshot, snapshot.id == user.id { return snapshot }
                let email = user.email ?? "linkup-user@linkup.local"
                let displayName = (user.userMetadata["display_name"]?.stringValue)
                    ?? email.components(separatedBy: "@").first?.capitalized
                    ?? "Linkup user"
                return makeAccount(
                    id: user.id,
                    displayName: displayName,
                    email: email,
                    method: .email,
                    appleSubject: nil,
                    googleSubject: nil
                )
            } catch {
                #if DEBUG
                print("[Linkup] Supabase session restore failed: \(error.localizedDescription)")
                #endif
                return nil
            }
        }
        #endif

        guard let token = keychain.read(),
              let accountID = token.components(separatedBy: ":").last else {
            return nil
        }
        return loadAccounts()[accountID]
    }

    func clearSession() {
        keychain.delete()
        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            Task { try? await supabase.auth.signOut() }
        }
        #endif
    }

    func resetAllAuthData() {
        keychain.delete()
        [Keys.accounts, Keys.emailCredentials, Keys.socialCredentials].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    // MARK: - Delete account (Apple App Store §5.1.1(v) requirement)

    /// Deletes the signed-in user's account.
    /// - Local fallback path: wipes credential stores so the user can re-create the account.
    /// - Supabase path: signs out + asks the backend to enqueue a server-side
    ///   deletion (the dedicated `/account/delete` endpoint must be implemented
    ///   on the Edge Function — see the follow-up note in the agent handoff).
    func deleteAccount(accountID: UUID) async throws {
        let baseURL = LinkupBackendService.configuredBaseURL()
        if let baseURL {
            do {
                try await LinkupBackendService().requestAccountDeletion(accountID: accountID, baseURL: baseURL)
            } catch {
                // Don't hard-fail the local cleanup if the backend isn't ready
                // yet — Apple's requirement is "the user can request deletion
                // from inside the app". Best-effort logging only.
                #if DEBUG
                print("[Linkup] backend deletion failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }

        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            try? await supabase.auth.signOut()
        }
        #endif

        // Local cleanup so the device is reset whether or not the backend ran.
        var accounts = loadAccounts()
        accounts.removeValue(forKey: accountID.uuidString)
        saveAccounts(accounts)

        var emailCreds = loadEmailCredentials()
        for (key, cred) in emailCreds where cred.accountID == accountID {
            emailCreds.removeValue(forKey: key)
        }
        saveEmailCredentials(emailCreds)

        var socialCreds = loadSocialCredentials()
        for (key, cred) in socialCreds where cred.accountID == accountID {
            socialCreds.removeValue(forKey: key)
        }
        saveSocialCredentials(socialCreds)

        keychain.delete()
    }

    // MARK: - Internal helpers

    private func completeSocialSignIn(
        method: AuthMethod,
        subject: String,
        name: String,
        email: String,
        idToken: String,
        nonce: String?
    ) async throws -> AuthenticatedAccount {
        #if canImport(Supabase)
        if let supabase = LinkupSupabase.shared {
            do {
                let provider: OpenIDConnectCredentials.Provider = (method == .apple) ? .apple : .google
                let session = try await supabase.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: provider,
                        idToken: idToken,
                        nonce: nonce
                    )
                )
                let user = session.user
                let resolvedName = name.isEmpty
                    ? ((user.userMetadata["display_name"]?.stringValue) ?? email)
                    : name
                let account = makeAccount(
                    id: user.id,
                    displayName: resolvedName,
                    email: email,
                    method: method,
                    appleSubject: method == .apple ? subject : nil,
                    googleSubject: method == .google ? subject : nil
                )
                return authenticated(account)
            } catch {
                throw AuthError.supabaseFailure(error.localizedDescription)
            }
        }
        #endif

        return upsertSocialAccount(method: method, subject: subject, name: name, email: email)
    }

    private func upsertSocialAccount(method: AuthMethod, subject: String, name: String, email: String) -> AuthenticatedAccount {
        var accounts = loadAccounts()
        var credentials = loadSocialCredentials()
        let key = "\(method.rawValue):\(subject)"
        let existingAccount = credentials[key].flatMap { accounts[$0.accountID.uuidString] }

        var account = existingAccount ?? makeAccount(
            id: UUID(),
            displayName: name.isEmpty ? "\(method.rawValue.capitalized) User" : name,
            email: email.isEmpty ? "\(subject)@linkup.local" : email,
            method: method,
            appleSubject: method == .apple ? subject : nil,
            googleSubject: method == .google ? subject : nil
        )

        if !name.isEmpty {
            account.displayName = name
        }
        if !email.isEmpty {
            account.email = email
        }
        account.lastSignedInAt = Date()
        if method == .apple { account.appleSubject = subject }
        if method == .google { account.googleSubject = subject }
        accounts[account.id.uuidString] = account
        credentials[key] = SocialCredential(accountID: account.id, provider: method, subject: subject, email: email)
        saveAccounts(accounts)
        saveSocialCredentials(credentials)
        return authenticated(account)
    }

    private func makeAccount(
        id: UUID,
        displayName: String,
        email: String,
        method: AuthMethod,
        appleSubject: String?,
        googleSubject: String?
    ) -> Account {
        Account(
            id: id,
            displayName: displayName,
            email: email,
            authMethod: method,
            appleSubject: appleSubject,
            googleSubject: googleSubject,
            linkedInConnected: false,
            linkedInURL: nil,
            linkedInImportedAt: nil,
            linkedInConnectionCount: 0,
            pushToken: nil,
            createdAt: Date(),
            lastSignedInAt: Date()
        )
    }

    private func authenticated(_ account: Account) -> AuthenticatedAccount {
        let sessionToken = "session:\(account.id.uuidString)"
        keychain.save(sessionToken)
        return AuthenticatedAccount(account: account, sessionToken: sessionToken)
    }

    private func persistUpdatedAccount(_ account: Account) {
        var accounts = loadAccounts()
        accounts[account.id.uuidString] = account
        saveAccounts(accounts)
    }

    private func normalizeEmail(_ email: String) throws -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else { throw AuthError.invalidEmail }
        return normalized
    }

    private func passwordHash(_ password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data("\(salt):\(password)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func loadAccounts() -> [String: Account] {
        defaults.decode([String: Account].self, forKey: Keys.accounts) ?? [:]
    }

    private func saveAccounts(_ accounts: [String: Account]) {
        defaults.encode(accounts, forKey: Keys.accounts)
    }

    private func loadEmailCredentials() -> [String: EmailPasswordCredential] {
        defaults.decode([String: EmailPasswordCredential].self, forKey: Keys.emailCredentials) ?? [:]
    }

    private func saveEmailCredentials(_ credentials: [String: EmailPasswordCredential]) {
        defaults.encode(credentials, forKey: Keys.emailCredentials)
    }

    private func loadSocialCredentials() -> [String: SocialCredential] {
        defaults.decode([String: SocialCredential].self, forKey: Keys.socialCredentials) ?? [:]
    }

    private func saveSocialCredentials(_ credentials: [String: SocialCredential]) {
        defaults.encode(credentials, forKey: Keys.socialCredentials)
    }

    private static func fragmentValue(_ name: String, in fragment: String) -> String? {
        fragment
            .components(separatedBy: "&")
            .compactMap { part -> (String, String)? in
                let pair = part.components(separatedBy: "=")
                guard pair.count == 2 else { return nil }
                return (pair[0], pair[1].removingPercentEncoding ?? pair[1])
            }
            .first(where: { $0.0 == name })?
            .1
    }

    private static func decodeJWTClaims(_ token: String) -> [String: Any] {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return [:] }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any] else {
            return [:]
        }
        return claims
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleContinuation?.resume(throwing: AuthError.appleCredentialMissing)
                appleContinuation = nil
                return
            }

            let subject = credential.user
            let email = credential.email ?? ""
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            let idToken: String? = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            let nonce = appleNonce
            appleNonce = nil

            do {
                let result: AuthenticatedAccount
                if let idToken {
                    result = try await completeSocialSignIn(
                        method: .apple,
                        subject: subject,
                        name: name,
                        email: email,
                        idToken: idToken,
                        nonce: nonce
                    )
                } else {
                    result = upsertSocialAccount(method: .apple, subject: subject, name: name, email: email)
                }
                appleContinuation?.resume(returning: result)
            } catch {
                appleContinuation?.resume(throwing: error)
            }
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            appleContinuation?.resume(throwing: error)
            appleContinuation = nil
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
