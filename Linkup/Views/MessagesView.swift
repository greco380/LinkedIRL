import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @State private var selectedProfile: ConnectionProfile?
    @State private var openRowID: String?
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HeaderView(title: "Messages", openSettings: openSettings)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AdBannerView()
                        .padding(.horizontal, 22)

                    AccountHero()
                        .padding(.horizontal, 22)

                    if let session = store.shareSession {
                        Text("At \(session.eventName)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 22)

                        Card {
                            LazyVStack(spacing: 0) {
                                ForEach(store.visibleConnections) { connection in
                                    MessageRow(connection: connection, openRowID: $openRowID) {
                                        selectedProfile = connection
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                    } else {
                        EmptyMessagesState {
                            store.selectedTab = .discover
                        }
                        .padding(.horizontal, 22)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileSheet(connection: profile)
        }
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    var connection: ConnectionProfile
    @Binding var openRowID: String?
    var action: () -> Void

    var body: some View {
        SwipeActionRow(
            id: connection.id,
            openRowID: $openRowID,
            minHeight: 68,
            onTap: action,
            onMute: { store.mute(connection) },
            onBlock: { store.block(connection) }
        ) {
            HStack(spacing: 12) {
                AvatarView(initials: connection.initials, colorHex: connection.colorHex)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(connection.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if store.isMuted(connection) {
                            Image(systemName: "bell.slash.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        Text("Here now")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.primaryDark)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.primaryLight, in: Capsule())
                    }

                    Text(lastSnippet)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textQuaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.rowDivider)
                .frame(height: 1)
                .padding(.leading, 72)
        }
    }

    private var lastSnippet: String {
        store.messagesByConnectionID[connection.id]?.last?.body ?? "Tap to start a conversation"
    }
}

private struct AccountHero: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Text(store.account?.initials ?? "ME")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(theme.primary, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.account?.displayName ?? "Your account")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(store.account?.email ?? "Manage your event network")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 9) {
                    AccountStat(value: "\(store.totalConnectionCount)", label: "Connections")
                    AccountStat(value: "\(store.pastChatConnectionCount)", label: "People chatted")
                    AccountStat(value: "\(store.previouslyAttendedEvents.count)", label: "Past events")
                }

                if !store.recentChatSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Recent chats")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.textSecondary)

                        ForEach(Array(store.recentChatSummaries.enumerated()), id: \.element.message.id) { _, summary in
                            HStack(spacing: 9) {
                                AvatarView(initials: summary.connection.initials, colorHex: summary.connection.colorHex, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.connection.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.textPrimary)
                                    Text(summary.message.body)
                                        .font(.caption2)
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Previously attended")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textSecondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(store.previouslyAttendedEvents.prefix(6))) { event in
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.caption2.weight(.bold))
                                    Text(event.name)
                                        .lineLimit(1)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.primaryDark)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(theme.primaryLight, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(18)
        }
    }
}

private struct AccountStat: View {
    @Environment(\.linkupTheme) private var theme
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyMessagesState: View {
    @Environment(\.linkupTheme) private var theme
    var action: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 16) {
                Image(systemName: "message.badge.waveform.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .frame(width: 62, height: 62)
                    .background(theme.primaryLight, in: Circle())

                VStack(spacing: 6) {
                    Text("No one here yet")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Share your location from Discover to see active connections and start a quick meetup chat.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                PrimaryButton(title: "Go to Discover", systemImage: "location.fill", action: action)
            }
            .padding(22)
        }
    }
}
