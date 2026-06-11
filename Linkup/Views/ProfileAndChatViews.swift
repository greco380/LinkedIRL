import SwiftUI

struct ProfileSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkupTheme) private var theme
    @State private var showChat = false
    var connection: ConnectionProfile

    /// Returns the LinkedIn picture URL only when the connection card matches
    /// the signed-in user — we don't have peer picture URLs yet.
    private func pictureURL(for connection: ConnectionProfile) -> URL? {
        guard let account = store.account else { return nil }
        if connection.id == account.id.uuidString { return account.linkedInPictureURL }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(theme.bgSecondary, in: Circle())
                }
                .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        // If the connection happens to be the signed-in user's
                        // own profile (e.g. previewing their own card) we have
                        // a LinkedIn picture URL on file. For peer connections
                        // this is nil, so we fall back to coloured initials.
                        AvatarView(
                            initials: connection.initials,
                            colorHex: connection.colorHex,
                            size: 72,
                            pictureURL: pictureURL(for: connection)
                        )
                        Text(connection.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(connection.headline)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 10)

                    HStack(spacing: 10) {
                        StatCard(value: connection.connectedYear, label: "Connected since")
                        StatCard(value: "\(connection.sharedEvents.count + (store.shareSession == nil ? 0 : 1))", label: "Shared events")
                        StatCard(value: "\(connection.yearsExperience)y", label: "Experience")
                    }

                    ProfileSection(title: "Bio") {
                        Text(connection.bio)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .foregroundStyle(theme.textSecondary)
                    }

                    ProfileSection(title: "Events you've been at together") {
                        VStack(spacing: 0) {
                            if let event = store.shareSession?.eventName {
                                EventHistoryRow(name: event, date: "Today", isActive: true)
                            }
                            ForEach(connection.sharedEvents) { event in
                                EventHistoryRow(name: event.name, date: event.dateLabel, isActive: false)
                            }
                        }
                    }

                    ProfileSection(title: "Career") {
                        Text("\(connection.yearsAtCurrentCompany) years at \(connection.currentCompany) - \(connection.yearsExperience) years total experience")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Let's chat", systemImage: "message.fill") {
                showChat = true
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(theme.bg.opacity(0.94))
        }
        .background(theme.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showChat) {
            ChatThreadView(connection: connection)
        }
    }
}

private struct StatCard: View {
    @Environment(\.linkupTheme) private var theme
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProfileSection<Content: View>: View {
    @Environment(\.linkupTheme) private var theme
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textSecondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventHistoryRow: View {
    @Environment(\.linkupTheme) private var theme
    var name: String
    var date: String
    var isActive: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: isActive ? "mappin.circle.fill" : "calendar")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isActive ? theme.primary : theme.textSecondary)
                .frame(width: 30, height: 30)
                .background((isActive ? theme.primaryLight : theme.bgSecondary), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    if isActive {
                        Text("Now")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.primaryDark)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.primaryLight, in: Capsule())
                    }
                }
                Text(date)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct ChatThreadView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkupTheme) private var theme
    @State private var draft = ""
    @State private var pendingMessageDelete: ChatMessage?
    @State private var showThreadDeleteConfirm = false
    var connection: ConnectionProfile

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 36, height: 36)
                }
                .foregroundStyle(theme.textPrimary)

                AvatarView(initials: connection.initials, colorHex: connection.colorHex, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text(store.shareSession.map { "At \($0.eventName)" } ?? "Active recently")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()

                // App Review expects per-user control over chat content (not
                // just account deletion). Menu surfaces a destructive "Delete
                // chat" action plus exit hatches.
                Menu {
                    Button(role: .destructive) {
                        showThreadDeleteConfirm = true
                    } label: {
                        Label("Delete chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.bg)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if let event = store.shareSession?.eventName {
                            Text("You and \(connection.name.components(separatedBy: " ").first ?? connection.name) are both at \(event).")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.primaryDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(theme.chatBannerBg, in: Capsule())
                        }

                        ForEach(store.messagesByConnectionID[connection.id] ?? []) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingMessageDelete = message
                                    } label: {
                                        Label("Delete message", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.messagesByConnectionID[connection.id]?.count ?? 0) {
                    if let last = store.messagesByConnectionID[connection.id]?.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .foregroundStyle(theme.textPrimary)
                    .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    store.sendMessage(to: connection, body: draft)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(theme.primary, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(14)
            .background(theme.surface)
        }
        .background(theme.bg.ignoresSafeArea())
        .onAppear {
            if draft.isEmpty {
                draft = store.prefill(for: connection)
            }
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: .init(
                get: { pendingMessageDelete != nil },
                set: { if !$0 { pendingMessageDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let msg = pendingMessageDelete {
                    store.deleteMessage(msg, connectionID: connection.id)
                }
                pendingMessageDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingMessageDelete = nil }
        } message: {
            Text("This message will be removed from your device. Deletion on the recipient's side requires our backend deletion endpoint.")
        }
        .alert("Delete chat?", isPresented: $showThreadDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deleteChat(with: connection)
                dismiss()
            }
        } message: {
            Text("This permanently removes every message in this conversation from your device.")
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.linkupTheme) private var theme
    var message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.sender == .me { Spacer(minLength: 46) }
            VStack(alignment: message.sender == .me ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(message.sender == .me ? .white : theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.sender == .me ? theme.primary : theme.chatBubbleThem,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .opacity(message.status == .sending ? 0.7 : 1)

                if message.sender == .me {
                    switch message.status {
                    case .sending:
                        Text("Sending...")
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    case .failed:
                        Text("Failed to send")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: 0xFF3B30))
                    case .sent:
                        EmptyView()
                    }
                }
            }
            if message.sender == .them { Spacer(minLength: 46) }
        }
    }
}
