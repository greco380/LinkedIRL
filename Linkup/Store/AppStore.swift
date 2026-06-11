import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var account: Account?
    @Published var settings: UserSettings
    @Published var shareSession: ShareSession?
    @Published var mutedConnectionIDs: Set<String>
    @Published var blockedConnectionIDs: Set<String>
    @Published var messagesByConnectionID: [String: [ChatMessage]]
    @Published var linkedInNetworkDatabase: LinkedInNetworkDatabase?
    @Published var toast: String?
    @Published var selectedTab: AppTab = .discover

    /// Connections the backend reports as live at the current event (real
    /// cross-device data). Populated by the presence poll while sharing.
    @Published var liveConnections: [ConnectionProfile] = []

    let connections = SampleData.connections

    /// When the Supabase backend URL is configured, Discover shows real live
    /// connections (`liveConnections`) instead of the built-in sample people.
    var isLiveBackendEnabled: Bool {
        LinkupBackendService.configuredBaseURL() != nil
    }

    private var presencePollTask: Task<Void, Never>?
    private var messagePollTask: Task<Void, Never>?
    private let presencePollInterval: UInt64 = 7_000_000_000 // 7s
    private let messagePollInterval: UInt64 = 7_000_000_000 // 7s
    private var lastMessagePollAt: Date?
    private var locationCancellable: Task<Void, Never>?
    private var lastPublishedAccuracy: Double?

    private let defaults: UserDefaults
    private let authService: AuthService
    private let permissionService = PermissionService()
    private let locationService = LocationService()
    private let linkedInImportService = LinkedInNetworkImportService()
    private let linkedInAPIImportService = LinkedInAPIImportService()
    private let notificationService = NotificationService.shared
    private var deviceTokenObserver: NSObjectProtocol?

    /// Mirrors the LinkedIn picture URL latched onto each account (Settings &
    /// ProfileSheet) without forcing the AsyncImage to refetch on every render.
    var accountPictureURL: URL? { account?.linkedInPictureURL }

    private enum Keys {
        static let account = "linkup.account"
        static let settings = "linkup.settings"
        static let shareSession = "linkup.shareSession"
        static let muted = "linkup.muted"
        static let blocked = "linkup.blocked"
        static let messages = "linkup.messages"
        static let networkPrefix = "linkup.linkedin.network."
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainSessionStore = KeychainSessionStore()) {
        self.defaults = defaults
        self.authService = AuthService(defaults: defaults, keychain: keychain)
        self.settings = defaults.decode(UserSettings.self, forKey: Keys.settings) ?? .defaults
        self.shareSession = defaults.decode(ShareSession.self, forKey: Keys.shareSession)
        self.mutedConnectionIDs = defaults.decode(Set<String>.self, forKey: Keys.muted) ?? []
        self.blockedConnectionIDs = defaults.decode(Set<String>.self, forKey: Keys.blocked) ?? []
        self.messagesByConnectionID = defaults.decode([String: [ChatMessage]].self, forKey: Keys.messages) ?? [:]
        self.linkedInNetworkDatabase = nil

        // Synchronous warm-start: pull the cached Account snapshot so the UI
        // doesn't flash to the Login screen while Supabase resolves the session.
        if let snapshot = defaults.decode(Account.self, forKey: Keys.account) {
            self.account = snapshot
            self.linkedInNetworkDatabase = defaults.decode(LinkedInNetworkDatabase.self, forKey: networkKey(for: snapshot.id))
        }

        deviceTokenObserver = NotificationCenter.default.addObserver(
            forName: NotificationService.deviceTokenDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? String else { return }
            Task { @MainActor in
                self?.updatePushToken(token)
            }
        }

        expireShareSessionIfNeeded(showToast: false)

        // Reconcile against the real auth backend on launch. If the cached
        // snapshot is stale (e.g. user signed out on another device), this
        // promotes/clears `account` and starts/stops live features as needed.
        Task { [weak self] in
            guard let self else { return }
            await self.reconcileSessionOnLaunch()
        }
    }

    deinit {
        if let deviceTokenObserver {
            NotificationCenter.default.removeObserver(deviceTokenObserver)
        }
    }

    var theme: LinkupTheme {
        settings.theme == .light ? .light : .dark
    }

    var visibleConnections: [ConnectionProfile] {
        guard let shareSession else { return [] }
        // With the backend wired, show real connections reported live at the
        // event. Without it, fall back to the built-in sample set so the app
        // still demos on a single device.
        let source = isLiveBackendEnabled ? liveConnections : connections
        return source.filter {
            !isHiddenConnectionID($0.id) &&
            !shareSession.hiddenFromConnectionIDs.contains($0.id)
        }
    }

    var totalConnectionCount: Int {
        let importedCount = linkedInNetworkDatabase?.count ?? account?.linkedInConnectionCount ?? 0
        return max(importedCount, connections.count)
    }

    var pastChatConnectionCount: Int {
        messagesByConnectionID.values.filter { !$0.isEmpty }.count
    }

    var recentChatSummaries: [(connection: ConnectionProfile, message: ChatMessage)] {
        messagesByConnectionID
            .compactMap { id, messages -> (ConnectionProfile, ChatMessage)? in
                guard !isHiddenConnectionID(id),
                      let connection = connection(withID: id),
                      let message = messages.last else { return nil }
                return (connection, message)
            }
            .sorted { $0.1.sentAt > $1.1.sentAt }
            .prefix(3)
            .map { ($0.0, $0.1) }
    }

    var previouslyAttendedEvents: [SharedEvent] {
        var seen: Set<String> = []
        return connections
            .flatMap(\.sharedEvents)
            .filter { event in
                if seen.contains(event.name) {
                    return false
                }
                seen.insert(event.name)
                return true
            }
    }

    func createEmailAccount(name: String, email: String, password: String) {
        Task {
            do {
                let result = try await authService.createEmailAccount(name: name, email: email, password: password)
                finishAuthentication(result)
                showToast("Account created")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func signInEmail(email: String, password: String) {
        Task {
            do {
                let result = try await authService.signInEmail(email: email, password: password)
                finishAuthentication(result)
                showToast("Signed in")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// Called on launch + whenever the foreground returns. Resolves the live
    /// Supabase session, merges in the cached product snapshot, and starts the
    /// presence/message loops when an account is present.
    private func reconcileSessionOnLaunch() async {
        let restored = await authService.restoreSession()
        if let restored {
            if let snapshot = defaults.decode(Account.self, forKey: Keys.account), snapshot.id == restored.id {
                account = mergedAccount(authAccount: restored, productSnapshot: snapshot)
            } else {
                account = restored
            }
            if let account {
                linkedInNetworkDatabase = defaults.decode(LinkedInNetworkDatabase.self, forKey: networkKey(for: account.id))
                persistAccount()
            }
            if let shareSession, account != nil {
                startLivePresence(for: shareSession)
            }
            startMessagePollingIfPossible()
        } else if account != nil && LinkupSupabase.shared != nil {
            // Supabase says no session, but we have a cached account — the
            // user must have signed out elsewhere. Drop local state.
            stopLivePresence()
            stopMessagePolling()
            account = nil
            shareSession = nil
            defaults.removeObject(forKey: Keys.account)
            defaults.removeObject(forKey: Keys.shareSession)
        }
    }

    func signInWithApple() {
        Task {
            do {
                finishAuthentication(try await authService.signInWithApple())
                showToast("Signed in with Apple")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func signInWithGoogle() {
        Task {
            do {
                finishAuthentication(try await authService.signInWithGoogle())
                showToast("Signed in with Google")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    private func finishAuthentication(_ authenticated: AuthenticatedAccount) {
        if let snapshot = defaults.decode(Account.self, forKey: Keys.account), snapshot.id == authenticated.account.id {
            account = mergedAccount(authAccount: authenticated.account, productSnapshot: snapshot)
        } else {
            account = authenticated.account
        }
        linkedInNetworkDatabase = defaults.decode(LinkedInNetworkDatabase.self, forKey: networkKey(for: authenticated.account.id))
        persistAccount()
        permissionService.requestOnboardingPermissions()
        startMessagePollingIfPossible()
    }

    func signOut() {
        stopLivePresence()
        stopMessagePolling()
        account = nil
        shareSession = nil
        notificationService.cancelShareNotifications()
        authService.clearSession()
        defaults.removeObject(forKey: Keys.account)
        defaults.removeObject(forKey: Keys.shareSession)
        selectedTab = .discover
        showToast("Signed out")
    }

    /// Apple's App Store guideline 5.1.1(v) requires every account-creating app
    /// to expose an in-app deletion flow. This first asks the backend to wipe
    /// the server rows (auth user + all linked tables), then runs the same
    /// destructive local cleanup as `signOut` + `resetPrototype` and routes
    /// back to LoginView. Backend deletion is best-effort: if it fails the
    /// local state is still cleared so the user has a clean device.
    func deleteAccount() async {
        guard let accountID = account?.id else { return }
        stopLivePresence()
        stopMessagePolling()
        do {
            try await authService.deleteAccount(accountID: accountID)
        } catch {
            #if DEBUG
            print("[Linkup] deleteAccount partial failure: \(error.localizedDescription)")
            #endif
        }

        // Local destructive cleanup — mirrors resetPrototype but scoped to the
        // current account so other cached accounts on the device survive.
        defaults.removeObject(forKey: networkKey(for: accountID))
        account = nil
        shareSession = nil
        mutedConnectionIDs = []
        blockedConnectionIDs = []
        messagesByConnectionID = [:]
        linkedInNetworkDatabase = nil
        notificationService.cancelShareNotifications()
        [Keys.account, Keys.shareSession, Keys.muted, Keys.blocked, Keys.messages].forEach {
            defaults.removeObject(forKey: $0)
        }
        selectedTab = .discover
        showToast("Account deleted")
    }

    func resetPrototype() {
        stopLivePresence()
        let accountID = account?.id
        account = nil
        settings = .defaults
        shareSession = nil
        mutedConnectionIDs = []
        blockedConnectionIDs = []
        messagesByConnectionID = [:]
        linkedInNetworkDatabase = nil
        notificationService.cancelShareNotifications()
        authService.resetAllAuthData()
        [Keys.account, Keys.settings, Keys.shareSession, Keys.muted, Keys.blocked, Keys.messages].forEach {
            defaults.removeObject(forKey: $0)
        }
        if let accountID {
            defaults.removeObject(forKey: networkKey(for: accountID))
        }
    }

    func startSharing(hours: Int, eventName: String) {
        let trimmedEvent = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEvent = trimmedEvent.isEmpty ? "this event" : trimmedEvent
        // Clamp once so the actual share window and the toast/notifications all
        // agree. Previously the toast echoed the raw `hours` while the session
        // used the clamped value, so an out-of-range input showed a wrong duration.
        let clampedHours = max(1, min(15, hours))
        shareSession = ShareSession(
            id: UUID(),
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(clampedHours * 3600)),
            eventName: resolvedEvent,
            hiddenFromConnectionIDs: []
        )
        persistShareSession()
        if let shareSession {
            notificationService.scheduleShareNotifications(session: shareSession, expiringEnabled: settings.notifExpiring)
            startLivePresence(for: shareSession)
        }
        showToast("Sharing for \(clampedHours)h - \(resolvedEvent)")
    }

    func stopSharing() {
        let stoppedEvent = shareSession?.eventName
        shareSession = nil
        stopLivePresence()
        notificationService.deliverLocationStopped(eventName: stoppedEvent)
        persistShareSession()
        showToast("Sharing stopped")
    }

    func block(_ connection: ConnectionProfile) {
        blockedConnectionIDs.insert(connection.id)
        shareSession?.hiddenFromConnectionIDs.insert(connection.id)
        persistBlocked()
        persistShareSession()
        showToast("\(connection.name) blocked")
    }

    func mute(_ connection: ConnectionProfile) {
        mutedConnectionIDs.insert(connection.id)
        persistMuted()
        showToast("Notifications muted for \(connection.name)")
    }

    func isMuted(_ connection: ConnectionProfile) -> Bool {
        mutedConnectionIDs.contains(connection.id)
    }

    func connection(withID id: String) -> ConnectionProfile? {
        // Live presences first: real peers are keyed by account UUID and only
        // exist in `liveConnections`, so without this lookup their names never
        // resolve in notifications or recent-chat rows.
        liveConnections.first { $0.id == id } ?? connections.first { $0.id == id }
    }

    func setTheme(_ theme: ThemeChoice) {
        settings.theme = theme
        persistSettings()
    }

    func setAudience(_ audience: Audience) {
        settings.audience = audience
        persistSettings()
    }

    func updateDefaultShareHours(by delta: Int) {
        let options = [1, 2, 3, 4, 8, 12, 15]
        let currentIndex = options.firstIndex(of: settings.defaultShareHours) ?? options.firstIndex { $0 > settings.defaultShareHours } ?? 0
        let nextIndex = max(0, min(options.count - 1, currentIndex + delta))
        settings.defaultShareHours = options[nextIndex]
        persistSettings()
    }

    func setToggle(_ keyPath: WritableKeyPath<UserSettings, Bool>, to value: Bool) {
        settings[keyPath: keyPath] = value
        persistSettings()
    }

    func saveLinkedInProfile(url: String) throws {
        guard let accountID = account?.id else { return }
        let normalizedURL = try linkedInImportService.normalizedProfileURL(url)
        account?.linkedInConnected = true
        account?.linkedInURL = normalizedURL
        account?.linkedInProfileSlug = linkedInImportService.profileSlug(from: normalizedURL)
        account?.linkedInVerifiedAt = Date()
        account?.linkedInImportedAt = Date()
        account?.linkedInConnectionCount = linkedInNetworkDatabase?.count ?? 0
        let existingDatabase = linkedInNetworkDatabase
        linkedInNetworkDatabase = LinkedInNetworkDatabase(
            accountID: accountID,
            profileURL: normalizedURL,
            profiles: existingDatabase?.profiles ?? [],
            connections: existingDatabase?.connections ?? [],
            importedAt: existingDatabase?.importedAt ?? Date(),
            imports: existingDatabase?.imports ?? [],
            profileObservations: existingDatabase?.profileObservations ?? []
        )
        persistAccount()
        persistLinkedInNetwork()
        showToast("LinkedIn profile saved")
    }

    func importLinkedInConnections(from fileURL: URL, source: LinkedInImportSource = .csvExport) throws {
        guard let accountID = account?.id else { return }
        let profileURL = account?.linkedInURL ?? ""
        let existingImports = linkedInNetworkDatabase?.imports ?? []
        let existingObservations = linkedInNetworkDatabase?.profileObservations ?? []
        let importResult = try linkedInImportService.importConnections(from: fileURL, accountID: accountID, source: source)
        linkedInNetworkDatabase = LinkedInNetworkDatabase(
            accountID: accountID,
            profileURL: profileURL,
            profiles: importResult.profiles,
            connections: importResult.connections,
            importedAt: importResult.importRecord.importedAt,
            imports: existingImports + [importResult.importRecord],
            profileObservations: existingObservations + importResult.profileObservations
        )
        account?.linkedInConnected = true
        account?.linkedInImportedAt = Date()
        account?.linkedInConnectionCount = importResult.connections.count
        persistAccount()
        persistLinkedInNetwork()
        syncArchiveToBackend(accountID: accountID, result: importResult)
        showToast("\(importResult.connections.count) LinkedIn connections imported")
    }

    /// Best-effort push of a successful local CSV import to the Supabase Edge
    /// Function. The local import is already saved and shown to the user; a
    /// network/backend failure here is logged (DEBUG) and intentionally swallowed
    /// so it can never undo or block the local result. No-ops until the backend
    /// base URL is configured in Info.plist.
    private func syncArchiveToBackend(accountID: UUID, result: LinkedInConnectionImportResult) {
        guard let baseURL = LinkupBackendService.configuredBaseURL() else { return }
        Task {
            do {
                try await LinkupBackendService().syncArchive(accountID: accountID, result: result, baseURL: baseURL)
            } catch {
                #if DEBUG
                print("[Linkup] archive backend sync failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Live presence (real-time discovery across devices)

    /// Publishes the signed-in account's presence at the event and starts
    /// polling for which of their connections are live at the same event.
    /// No-ops cleanly when the backend URL isn't configured.
    func startLivePresence(for session: ShareSession) {
        guard isLiveBackendEnabled,
              let account,
              let baseURL = LinkupBackendService.configuredBaseURL() else { return }

        // Kick off CoreLocation so subsequent presence upserts carry the real
        // lat/lng. The first fix may not arrive before the first upsert; that's
        // fine — we'll re-publish whenever `lastLocation` changes (below).
        locationService.start()
        observeLocationUpdates(account: account, session: session, baseURL: baseURL)

        publishPresence(account: account, session: session, baseURL: baseURL)

        presencePollTask?.cancel()
        let service = LinkupBackendService()
        let accountID = account.id
        let eventName = session.eventName
        presencePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let nearby = try await service.fetchNearby(accountID: accountID, eventName: eventName, baseURL: baseURL)
                    if Task.isCancelled { return }
                    self.liveConnections = nearby.map { Self.connectionProfile(from: $0) }
                } catch {
                    #if DEBUG
                    print("[Linkup] presence poll failed (non-fatal): \(error.localizedDescription)")
                    #endif
                }
                try? await Task.sleep(nanoseconds: self.presencePollInterval)
            }
        }
    }

    /// Watches `LocationService.lastLocation` and re-publishes presence as the
    /// device moves. We don't have Combine plumbed in here so we just poll
    /// the `@Published` value at the same cadence as the presence loop.
    private func observeLocationUpdates(account: Account, session: ShareSession, baseURL: URL) {
        locationCancellable?.cancel()
        let accountID = account.id
        let expiresAt = session.expiresAt
        locationCancellable = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s (PRD §6 foreground cadence)
                if Task.isCancelled { return }
                // Bail out if the share session ended underneath us.
                guard self.shareSession?.id == session.id,
                      self.account?.id == accountID,
                      Date() < expiresAt else { return }
                self.publishPresence(account: self.account ?? account, session: session, baseURL: baseURL)
            }
        }
    }

    private func publishPresence(account: Account, session: ShareSession, baseURL: URL) {
        let service = LinkupBackendService()
        let accountID = account.id
        let displayName = account.displayName
        let headline = account.linkedInConnected ? "Connected on LinkedIn" : ""
        let slug = account.linkedInProfileSlug
        let url = account.linkedInURL
        let eventName = session.eventName
        let expiresAt = session.expiresAt
        let liveFix = locationService.lastLocation
        let position = Self.mapPosition(for: accountID, location: liveFix)
        let lat = liveFix?.coordinate.latitude
        let lng = liveFix?.coordinate.longitude
        let accuracy = liveFix?.horizontalAccuracy
        lastPublishedAccuracy = accuracy

        Task {
            do {
                try await service.upsertPresence(
                    accountID: accountID,
                    displayName: displayName,
                    headline: headline,
                    linkedInSlug: slug,
                    linkedInURL: url,
                    eventName: eventName,
                    mapX: position.0,
                    mapY: position.1,
                    latitude: lat,
                    longitude: lng,
                    accuracyMeters: accuracy,
                    expiresAt: expiresAt,
                    baseURL: baseURL
                )
            } catch {
                #if DEBUG
                print("[Linkup] presence publish failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Stops broadcasting + polling and tells the backend to drop the presence row.
    func stopLivePresence() {
        presencePollTask?.cancel()
        presencePollTask = nil
        locationCancellable?.cancel()
        locationCancellable = nil
        locationService.stop()
        liveConnections = []
        guard isLiveBackendEnabled,
              let accountID = account?.id,
              let baseURL = LinkupBackendService.configuredBaseURL() else { return }
        Task {
            try? await LinkupBackendService().stopPresence(accountID: accountID, baseURL: baseURL)
        }
    }

    private static func connectionProfile(from presence: LivePresenceDTO) -> ConnectionProfile {
        let name = presence.displayName.isEmpty ? "LinkedIn connection" : presence.displayName
        let initials = name.initials.isEmpty ? "?" : name.initials
        return ConnectionProfile(
            id: presence.accountID,
            name: name,
            headline: presence.headline.isEmpty ? "At \(presence.eventName)" : presence.headline,
            initials: initials,
            colorHex: color(for: presence.accountID),
            connectedAtLabel: "Live now",
            yearsExperience: 0,
            yearsAtCurrentCompany: 0,
            bio: "",
            sharedEvents: [SharedEvent(name: presence.eventName, dateLabel: "Now")],
            mapX: presence.mapX,
            mapY: presence.mapY
        )
    }

    private static let avatarPalette = ["FF5E3A", "1F8A70", "3A6EA5", "C9457A", "E0A800", "6C5CE7", "00897B", "D7263D"]

    private static func color(for id: String) -> String {
        var hash = 5381
        for byte in id.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return avatarPalette[abs(hash) % avatarPalette.count]
    }

    /// Deterministic on-map position for an account so a sharer lands in the
    /// same spot for everyone (and across relaunches) rather than overlapping
    /// the centre "you" pin. When a real `CLLocation` is available we still
    /// produce a normalized [0, 1] map coordinate by hashing the rounded
    /// lat/lng — this keeps the venue map demoable until we wire up a real
    /// geofenced floor plan.
    private static func mapPosition(for id: UUID, location: CLLocation? = nil) -> (Double, Double) {
        if let location {
            // Quantize to ~10m precision then map into [0.1, 0.9] so two
            // nearby people don't perfectly overlap.
            let lat = (location.coordinate.latitude * 1000).truncatingRemainder(dividingBy: 1.0)
            let lng = (location.coordinate.longitude * 1000).truncatingRemainder(dividingBy: 1.0)
            let x = 0.15 + abs(lng) * 0.70
            let y = 0.24 + abs(lat) * 0.58
            return (min(0.9, max(0.1, x)), min(0.9, max(0.1, y)))
        }
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let x = 0.15 + (Double(bytes[0]) / 255.0) * 0.70
        let y = 0.24 + (Double(bytes[1]) / 255.0) * 0.58
        return (x, y)
    }

    /// Runs LinkedIn OAuth to verify the user's identity and link their LinkedIn member id
    /// to the Linkup account. Does NOT replace the connection list — the connection list comes
    /// from the LinkedIn data export (CSV archive) flow. This method merges the new import
    /// record into the existing network database rather than replacing it.
    func importLinkedInConnectionsFromAPI() async throws {
        guard let accountID = account?.id else { return }
        let importResult = try await linkedInAPIImportService.importConnections(accountID: accountID)
        let profileURL = importResult.member.profileURL ?? account?.linkedInURL ?? "urn:li:person:\(importResult.member.subject)"

        let existing = linkedInNetworkDatabase
        linkedInNetworkDatabase = LinkedInNetworkDatabase(
            accountID: accountID,
            profileURL: profileURL,
            profiles: (existing?.profiles ?? []) + importResult.profiles,
            connections: existing?.connections ?? [],
            importedAt: existing?.importedAt ?? importResult.importRecord.importedAt,
            imports: (existing?.imports ?? []) + [importResult.importRecord],
            profileObservations: (existing?.profileObservations ?? []) + importResult.profileObservations
        )

        account?.linkedInConnected = true
        account?.linkedInMemberID = importResult.member.subject
        account?.linkedInURL = importResult.member.profileURL ?? account?.linkedInURL
        account?.linkedInProfileSlug = importResult.member.profileSlug ?? account?.linkedInProfileSlug
        account?.linkedInPictureURL = importResult.member.picture ?? account?.linkedInPictureURL
        account?.linkedInVerifiedAt = importResult.member.verifiedAt ?? Date()
        // Leave linkedInImportedAt / linkedInConnectionCount untouched — those reflect the
        // CSV import. Only update them if no archive import has happened yet.
        if account?.linkedInImportedAt == nil {
            account?.linkedInImportedAt = importResult.importRecord.importedAt
        }
        persistAccount()
        persistLinkedInNetwork()
        showToast("LinkedIn identity verified")
    }

    func refreshLinkedIn() async {
        guard account?.linkedInConnected == true else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        account?.linkedInImportedAt = Date()
        account?.linkedInConnectionCount = linkedInNetworkDatabase?.count ?? account?.linkedInConnectionCount ?? 0
        persistAccount()
        showToast("Network database refreshed")
    }

    func disconnectLinkedIn() {
        account?.linkedInConnected = false
        account?.linkedInURL = nil
        account?.linkedInMemberID = nil
        account?.linkedInProfileSlug = nil
        account?.linkedInPictureURL = nil
        account?.linkedInVerifiedAt = nil
        account?.linkedInImportedAt = nil
        account?.linkedInConnectionCount = 0
        linkedInNetworkDatabase = nil
        persistAccount()
        removeLinkedInNetwork()
        showToast("LinkedIn disconnected")
    }

    func sendMessage(to connection: ConnectionProfile, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Optimistic insert. The `sending` state lets the chat bubble render
        // a subtle spinner / opacity until the backend confirms (or we mark
        // it failed for retry).
        let optimisticID = UUID()
        let optimistic = ChatMessage(
            id: optimisticID,
            connectionID: connection.id,
            sender: .me,
            body: trimmed,
            sentAt: Date(),
            status: isLiveBackendEnabled ? .sending : .sent
        )
        messagesByConnectionID[connection.id, default: []].append(optimistic)
        persistMessages()

        guard isLiveBackendEnabled,
              let senderID = account?.id,
              let baseURL = LinkupBackendService.configuredBaseURL(),
              let recipientID = UUID(uuidString: connection.id) else {
            // Local demo path: keep the canned-reply behavior so a single-device
            // demo still feels alive. Gated by `!isLiveBackendEnabled` so it
            // never runs in production.
            if !isLiveBackendEnabled {
                appendDemoReply(for: connection)
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let sent = try await LinkupBackendService().sendMessage(
                    senderID: senderID,
                    recipientID: recipientID,
                    body: trimmed,
                    baseURL: baseURL
                )
                self.mergeSentMessage(localID: optimisticID, connectionID: connection.id, dto: sent)
            } catch {
                self.markMessageFailed(localID: optimisticID, connectionID: connection.id)
                #if DEBUG
                print("[Linkup] sendMessage failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Local-only canned reply, used pre-backend (so the demo still feels
    /// responsive). Never runs when `isLiveBackendEnabled` is true.
    private func appendDemoReply(for connection: ConnectionProfile) {
        let replies = [
            "Great timing. I am near the demo floor.",
            "Yes, let's meet by the main stage.",
            "Perfect. I have ten minutes before my next session."
        ]
        let reply = ChatMessage(
            id: UUID(),
            connectionID: connection.id,
            sender: .them,
            body: replies.randomElement()!,
            sentAt: Date(),
            status: .sent
        )
        messagesByConnectionID[connection.id, default: []].append(reply)
        persistMessages()

        if settings.notifNewMessage, !isMuted(connection) {
            notificationService.deliverMessageNotification(
                from: connection,
                body: reply.body,
                eventName: shareSession?.eventName
            )
        }
    }

    /// Promote an optimistic local message to the canonical server row.
    private func mergeSentMessage(localID: UUID, connectionID: String, dto: ChatMessageDTO) {
        guard var messages = messagesByConnectionID[connectionID],
              let idx = messages.firstIndex(where: { $0.id == localID }) else { return }
        let serverID = UUID(uuidString: dto.id) ?? localID
        messages[idx] = ChatMessage(
            id: serverID,
            connectionID: connectionID,
            sender: .me,
            body: dto.body,
            sentAt: dto.sentAt,
            status: .sent
        )
        messagesByConnectionID[connectionID] = messages
        persistMessages()
    }

    private func markMessageFailed(localID: UUID, connectionID: String) {
        guard var messages = messagesByConnectionID[connectionID],
              let idx = messages.firstIndex(where: { $0.id == localID }) else { return }
        messages[idx].status = .failed
        messagesByConnectionID[connectionID] = messages
        persistMessages()
    }

    // MARK: - Real message polling (cross-device DMs)

    /// Starts the message-poll loop. Idempotent + safe to call from any state
    /// — short-circuits when the backend isn't configured or when no account
    /// is signed in.
    private func startMessagePollingIfPossible() {
        guard isLiveBackendEnabled,
              let accountID = account?.id,
              let baseURL = LinkupBackendService.configuredBaseURL() else { return }

        messagePollTask?.cancel()
        messagePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollMessagesOnce(accountID: accountID, baseURL: baseURL)
                try? await Task.sleep(nanoseconds: self.messagePollInterval)
            }
        }
    }

    private func stopMessagePolling() {
        messagePollTask?.cancel()
        messagePollTask = nil
        lastMessagePollAt = nil
    }

    private func pollMessagesOnce(accountID: UUID, baseURL: URL) async {
        do {
            let since = lastMessagePollAt
            let dtos = try await LinkupBackendService().pollMessages(
                accountID: accountID,
                since: since,
                baseURL: baseURL
            )
            guard !Task.isCancelled else { return }
            ingestPolledMessages(dtos, currentAccountID: accountID)
            if let newest = dtos.map(\.sentAt).max() {
                lastMessagePollAt = newest
            } else if since == nil {
                // First poll returned no messages; advance the cursor anyway
                // so the next poll only asks for new rows.
                lastMessagePollAt = Date()
            }
        } catch {
            #if DEBUG
            print("[Linkup] message poll failed (non-fatal): \(error.localizedDescription)")
            #endif
        }
    }

    private func ingestPolledMessages(_ dtos: [ChatMessageDTO], currentAccountID: UUID) {
        guard !dtos.isEmpty else { return }
        var didMutate = false
        for dto in dtos {
            // Connection key = the OTHER side of the conversation.
            let myID = currentAccountID.uuidString.lowercased()
            let otherID = dto.senderAccountID.lowercased() == myID
                ? dto.recipientAccountID
                : dto.senderAccountID
            let sender: ChatMessage.Sender = dto.senderAccountID.lowercased() == myID ? .me : .them
            let messageID = UUID(uuidString: dto.id) ?? UUID()

            var existing = messagesByConnectionID[otherID] ?? []
            if existing.contains(where: { $0.id == messageID }) {
                continue // already merged via the optimistic path
            }
            existing.append(ChatMessage(
                id: messageID,
                connectionID: otherID,
                sender: sender,
                body: dto.body,
                sentAt: dto.sentAt,
                status: .sent
            ))
            existing.sort { $0.sentAt < $1.sentAt }
            messagesByConnectionID[otherID] = existing
            didMutate = true

            // Local notification on receipt — only for incoming messages and
            // only when the user hasn't muted that connection.
            if sender == .them, settings.notifNewMessage {
                let connectionStub = connection(withID: otherID)
                    ?? ConnectionProfile(
                        id: otherID,
                        name: "LinkedIn connection",
                        headline: "",
                        initials: "?",
                        colorHex: "FF5E3A",
                        connectedAtLabel: "",
                        yearsExperience: 0,
                        yearsAtCurrentCompany: 0,
                        bio: "",
                        sharedEvents: [],
                        mapX: 0.5,
                        mapY: 0.5
                    )
                if !isMuted(connectionStub) {
                    notificationService.deliverMessageNotification(
                        from: connectionStub,
                        body: dto.body,
                        eventName: shareSession?.eventName
                    )
                }
            }
        }
        if didMutate {
            persistMessages()
        }
    }

    /// Deletes a single message from the user-visible thread + (best-effort)
    /// from the backend. Local removal is immediate so the UI feels snappy;
    /// a backend failure is logged but doesn't undo the local removal.
    func deleteMessage(_ message: ChatMessage, connectionID: String) {
        // Local optimistic removal.
        if var messages = messagesByConnectionID[connectionID] {
            messages.removeAll { $0.id == message.id }
            messagesByConnectionID[connectionID] = messages
            persistMessages()
        }

        guard isLiveBackendEnabled,
              let accountID = account?.id,
              let baseURL = LinkupBackendService.configuredBaseURL() else { return }

        Task {
            do {
                try await LinkupBackendService().deleteMessage(
                    id: message.id,
                    accountID: accountID,
                    baseURL: baseURL
                )
            } catch {
                #if DEBUG
                print("[Linkup] message delete failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Deletes the full thread with `connection`. Local cleanup is immediate;
    /// the backend call is best-effort (endpoint may not exist yet).
    func deleteChat(with connection: ConnectionProfile) {
        messagesByConnectionID.removeValue(forKey: connection.id)
        persistMessages()

        guard isLiveBackendEnabled,
              let accountID = account?.id,
              let baseURL = LinkupBackendService.configuredBaseURL(),
              let otherID = UUID(uuidString: connection.id) else { return }

        Task {
            do {
                try await LinkupBackendService().deleteThread(
                    accountID: accountID,
                    otherAccountID: otherID,
                    baseURL: baseURL
                )
            } catch {
                #if DEBUG
                print("[Linkup] thread delete failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func prefill(for connection: ConnectionProfile) -> String {
        if let event = shareSession?.eventName {
            return "I'm at \(event) too, where should we meet?"
        }
        return "Looks like we are both nearby, where should we meet?"
    }

    func expireShareSessionIfNeeded(showToast shouldToast: Bool = true) {
        if shareSession?.isExpired == true {
            shareSession = nil
            stopLivePresence()
            persistShareSession()
            if shouldToast {
                showToast("Sharing expired")
            }
        }
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == message {
                toast = nil
            }
        }
    }

    private func persistAccount() {
        if let account {
            defaults.encode(account, forKey: Keys.account)
        } else {
            defaults.removeObject(forKey: Keys.account)
        }
    }

    private func updatePushToken(_ token: String) {
        account?.pushToken = token
        persistAccount()
    }

    private func persistSettings() {
        defaults.encode(settings, forKey: Keys.settings)
    }

    private func persistShareSession() {
        if let shareSession {
            defaults.encode(shareSession, forKey: Keys.shareSession)
        } else {
            defaults.removeObject(forKey: Keys.shareSession)
        }
    }

    private func persistMuted() {
        defaults.encode(mutedConnectionIDs, forKey: Keys.muted)
    }

    private func persistBlocked() {
        defaults.encode(blockedConnectionIDs, forKey: Keys.blocked)
    }

    private func persistMessages() {
        defaults.encode(messagesByConnectionID, forKey: Keys.messages)
    }

    private func isHiddenConnectionID(_ id: String) -> Bool {
        blockedConnectionIDs.contains(id) || mutedConnectionIDs.contains(id)
    }

    private func persistLinkedInNetwork() {
        guard let accountID = account?.id, let linkedInNetworkDatabase else { return }
        defaults.encode(linkedInNetworkDatabase, forKey: networkKey(for: accountID))
    }

    private func removeLinkedInNetwork() {
        guard let accountID = account?.id else { return }
        defaults.removeObject(forKey: networkKey(for: accountID))
    }

    private func networkKey(for accountID: UUID) -> String {
        "\(Keys.networkPrefix)\(accountID.uuidString)"
    }

    private func mergedAccount(authAccount: Account, productSnapshot: Account) -> Account {
        var merged = productSnapshot
        merged.displayName = authAccount.displayName
        merged.email = authAccount.email
        merged.authMethod = authAccount.authMethod
        merged.appleSubject = authAccount.appleSubject
        merged.googleSubject = authAccount.googleSubject
        merged.lastSignedInAt = authAccount.lastSignedInAt
        // Picture URL flows from LinkedIn verification, which lives on the
        // product snapshot — preserve it on auth refresh.
        if productSnapshot.linkedInPictureURL != nil {
            merged.linkedInPictureURL = productSnapshot.linkedInPictureURL
        }
        return merged
    }
}

enum AppTab: String, CaseIterable {
    case discover, messages

    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .discover: "location.fill"
        case .messages: "message.fill"
        }
    }
}

extension UserDefaults {
    func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
