import Foundation

/// Request body for POST /linkedin/archive/sync. Mirrors the Edge Function's
/// `SyncRequest`. Encoded with `.iso8601` dates so Postgres `timestamptz`
/// columns accept the values directly.
struct LinkupArchiveSyncRequest: Encodable {
    let accountID: String
    let importRecord: LinkedInImportRecord
    let profiles: [LinkedInProfileRecord]
    let connections: [LinkedInNetworkConnection]
    let profileObservations: [LinkedInProfileObservation]
}

/// Thin client for Linkup Supabase Edge Function endpoints that sit outside the
/// interactive OAuth flow. Currently just archive sync: persisting a locally
/// parsed LinkedIn CSV import server-side so the network is uniform across
/// devices. This is intentionally best-effort — the locally stored import is the
/// source of truth, and a sync failure must never lose or block it.
struct LinkupBackendService {
    enum BackendError: LocalizedError {
        case missingAPIBaseURL
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIBaseURL:
                return "Linkup API base URL is not configured."
            case .requestFailed(let message):
                return message
            }
        }
    }

    /// Reads `LINKUP_API_BASE_URL` from Info.plist, returning nil while it is
    /// still a placeholder. Lets callers no-op cleanly before the backend is wired.
    static func configuredBaseURL(bundle: Bundle = .main) -> URL? {
        usableBaseURL(from: bundle.object(forInfoDictionaryKey: "LINKUP_API_BASE_URL") as? String)
    }

    /// Pure validation of a candidate base-URL string. Rejects empty values and
    /// the Info.plist placeholder markers so the sync call no-ops until Josh
    /// fills in the deployed function URL. Extracted for unit testing.
    static func usableBaseURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("#######"),
              !trimmed.contains("REPLACE_WITH"),
              let url = URL(string: trimmed),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    func syncArchive(accountID: UUID, result: LinkedInConnectionImportResult, baseURL: URL) async throws {
        guard let endpoint = Self.endpoint(path: "linkedin/archive/sync", baseURL: baseURL) else {
            throw BackendError.missingAPIBaseURL
        }

        let payload = LinkupArchiveSyncRequest(
            accountID: accountID.uuidString,
            importRecord: result.importRecord,
            profiles: result.profiles,
            connections: result.connections,
            profileObservations: result.profileObservations
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw BackendError.requestFailed(message)
        }
    }

    /// Joins a path onto the configured base URL, preserving any base path
    /// (e.g. `/functions/v1/linkedin-oauth`). Mirrors the OAuth service's logic.
    static func endpoint(path: String, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let combined = ([basePath, path].filter { !$0.isEmpty }).joined(separator: "/")
        components?.path = "/\(combined)"
        return components?.url
    }
}

// MARK: - Live presence (real-time "who's at this event")

/// One live broadcast returned by POST /presence/nearby. Mirrors the Edge
/// Function's response shape. Only connections the requester is allowed to see
/// are returned (the matching happens server-side).
struct LivePresenceDTO: Decodable, Equatable {
    let accountID: String
    let displayName: String
    let headline: String
    let linkedInSlug: String?
    let linkedInURL: String?
    let eventName: String
    let mapX: Double
    let mapY: Double
    let startedAt: Date
    let expiresAt: Date
}

private struct PresenceUpsertBody: Encodable {
    let accountID: String
    let displayName: String
    let headline: String
    let linkedInSlug: String?
    let linkedInURL: String?
    let eventName: String
    let mapX: Double
    let mapY: Double
    // Real CoreLocation coordinates. Optional — synthetic positions skip these.
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
    let expiresAt: Date
}

private struct PresenceStopBody: Encodable {
    let accountID: String
}

private struct PresenceNearbyBody: Encodable {
    let accountID: String
    let eventName: String
}

private struct PresenceNearbyResponse: Decodable {
    let presences: [LivePresenceDTO]
}

extension LinkupBackendService {
    private static func iso8601Encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Publishes (or refreshes) the signed-in account's live presence at an event.
    /// `latitude` / `longitude` / `accuracyMeters` carry the real CoreLocation
    /// fix when one is available; they're nil while the device is still
    /// resolving its first fix (in which case only the synthetic mapX/mapY pin
    /// is shown to other devices).
    func upsertPresence(
        accountID: UUID,
        displayName: String,
        headline: String,
        linkedInSlug: String?,
        linkedInURL: String?,
        eventName: String,
        mapX: Double,
        mapY: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        expiresAt: Date,
        baseURL: URL
    ) async throws {
        let body = PresenceUpsertBody(
            accountID: accountID.uuidString,
            displayName: displayName,
            headline: headline,
            linkedInSlug: linkedInSlug,
            linkedInURL: linkedInURL,
            eventName: eventName,
            mapX: mapX,
            mapY: mapY,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
            expiresAt: expiresAt
        )
        _ = try await post(path: "presence/upsert", body: body, baseURL: baseURL)
    }

    /// Removes the account's live presence (called when sharing stops or expires).
    func stopPresence(accountID: UUID, baseURL: URL) async throws {
        _ = try await post(path: "presence/stop", body: PresenceStopBody(accountID: accountID.uuidString), baseURL: baseURL)
    }

    /// Fetches the connections currently live at the same event. Server-side
    /// matching guarantees only the requester's own connections come back.
    func fetchNearby(accountID: UUID, eventName: String, baseURL: URL) async throws -> [LivePresenceDTO] {
        let data = try await post(
            path: "presence/nearby",
            body: PresenceNearbyBody(accountID: accountID.uuidString, eventName: eventName),
            baseURL: baseURL
        )
        return (try? Self.iso8601Decoder().decode(PresenceNearbyResponse.self, from: data))?.presences ?? []
    }

    // MARK: - Messaging (cross-device DMs, replaces canned-reply demo)

    /// Sends a message to another Linkup user. Returns the server-side row so
    /// the caller can swap the optimistic local message for the canonical one
    /// (same id from the optimistic side is fine — server assigns its own).
    func sendMessage(
        senderID: UUID,
        recipientID: UUID,
        body text: String,
        baseURL: URL
    ) async throws -> ChatMessageDTO {
        let data = try await post(
            path: "messages/send",
            body: MessageSendBody(
                senderAccountID: senderID.uuidString,
                recipientAccountID: recipientID.uuidString,
                body: text
            ),
            baseURL: baseURL
        )
        let decoded = try Self.iso8601Decoder().decode(MessageSendResponse.self, from: data)
        return decoded.message
    }

    /// Polls all messages (sent + received) for `accountID` since `since`. Used
    /// by AppStore's poll loop to hydrate `messagesByConnectionID`.
    func pollMessages(
        accountID: UUID,
        since: Date?,
        baseURL: URL
    ) async throws -> [ChatMessageDTO] {
        let data = try await post(
            path: "messages/poll",
            body: MessagePollBody(
                accountID: accountID.uuidString,
                sinceISO: since.map { Self.iso8601Formatter.string(from: $0) }
            ),
            baseURL: baseURL
        )
        let decoded = try Self.iso8601Decoder().decode(MessagePollResponse.self, from: data)
        return decoded.messages
    }

    /// Lists chat threads (one per unique counterparty) for the inbox view.
    func fetchThreads(
        accountID: UUID,
        baseURL: URL
    ) async throws -> [ChatThreadDTO] {
        let data = try await post(
            path: "messages/threads",
            body: MessageThreadsBody(accountID: accountID.uuidString),
            baseURL: baseURL
        )
        let decoded = try Self.iso8601Decoder().decode(MessageThreadsResponse.self, from: data)
        return decoded.threads
    }

    /// Requests deletion of a single message from a thread. Currently posts to
    /// the not-yet-implemented `/messages/delete` endpoint; callers (AppStore)
    /// must tolerate a 404 (display a toast, leave the message in place) until
    /// the backend lands.
    func deleteMessage(id: UUID, accountID: UUID, baseURL: URL) async throws {
        _ = try await post(
            path: "messages/delete",
            body: MessageDeleteBody(
                messageID: id.uuidString,
                accountID: accountID.uuidString
            ),
            baseURL: baseURL
        )
    }

    /// Requests deletion of every message in a thread (both directions). Used
    /// by the per-thread "Delete chat" affordance.
    func deleteThread(accountID: UUID, otherAccountID: UUID, baseURL: URL) async throws {
        _ = try await post(
            path: "messages/delete",
            body: MessageDeleteBody(
                messageID: nil,
                accountID: accountID.uuidString,
                otherAccountID: otherAccountID.uuidString
            ),
            baseURL: baseURL
        )
    }

    // MARK: - Account deletion (App Store §5.1.1(v) requirement)

    /// Asks the backend to permanently delete the account + every row tied to
    /// it (linkup_account, linkedin_*, live_presence, chat_message). Posts to
    /// the not-yet-implemented `/account/delete` endpoint; the iOS UX has to
    /// finish wiping local state regardless of the response so the user can
    /// reclaim their device immediately.
    func requestAccountDeletion(accountID: UUID, baseURL: URL) async throws {
        _ = try await post(
            path: "account/delete",
            body: AccountDeleteBody(accountID: accountID.uuidString),
            baseURL: baseURL
        )
    }

    /// Shared POST helper: encodes the body with ISO-8601 dates, checks the
    /// status, and surfaces the server's `error` message on failure.
    private func post<Body: Encodable>(path: String, body: Body, baseURL: URL) async throws -> Data {
        guard let endpoint = Self.endpoint(path: path, baseURL: baseURL) else {
            throw BackendError.missingAPIBaseURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Self.iso8601Encoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw BackendError.requestFailed(message)
        }
        return data
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Messaging DTOs

/// Mirror of the Edge Function's `toChatMessageDTO` shape.
struct ChatMessageDTO: Decodable, Equatable {
    let id: String
    let threadID: String
    let senderAccountID: String
    let recipientAccountID: String
    let body: String
    let sentAt: Date
    let deliveredAt: Date?
    let readAt: Date?
}

/// One thread row returned by `/messages/threads`.
struct ChatThreadDTO: Decodable, Equatable {
    let threadID: String
    let otherAccountID: String
    let lastBody: String
    let lastSentAt: Date
    let lastSenderAccountID: String
    let unreadCount: Int
}

private struct MessageSendBody: Encodable {
    let senderAccountID: String
    let recipientAccountID: String
    let body: String
}

private struct MessageSendResponse: Decodable {
    let message: ChatMessageDTO
}

private struct MessagePollBody: Encodable {
    let accountID: String
    let sinceISO: String?
}

private struct MessagePollResponse: Decodable {
    let messages: [ChatMessageDTO]
}

private struct MessageThreadsBody: Encodable {
    let accountID: String
}

private struct MessageThreadsResponse: Decodable {
    let threads: [ChatThreadDTO]
}

private struct MessageDeleteBody: Encodable {
    var messageID: String?
    var accountID: String
    var otherAccountID: String? = nil
}

private struct AccountDeleteBody: Encodable {
    let accountID: String
}
