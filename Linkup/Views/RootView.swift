import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            if store.account == nil {
                LoginView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                MainAppView()
                    .transition(.opacity)
            }

            // Toast lives at the root so feedback (including login/sign-up errors)
            // is visible on the LoginView too, not just once the user is signed in.
            if let toast = store.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast)
                        .padding(.bottom, store.account == nil ? 40 : 78)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: store.account == nil)
        .animation(.easeInOut(duration: 0.2), value: store.toast)
    }
}

struct MainAppView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        switch store.selectedTab {
                        case .discover:
                            DiscoverView(openSettings: { showSettings = true })
                        case .messages:
                            MessagesView(openSettings: { showSettings = true })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinkupTabBar()
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                store.expireShareSessionIfNeeded()
            }
        }
    }
}

struct LinkupTabBar: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    store.selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(store.selectedTab == tab ? theme.primary : theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    var title: String
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(theme.bgSecondary, in: Circle())
                        .foregroundStyle(theme.textPrimary)
                }
                .accessibilityLabel("Settings")
            }

            if let session = store.shareSession {
                HStack(spacing: 7) {
                    Circle()
                        .fill(theme.primary)
                        .frame(width: 7, height: 7)
                    Text("\(session.eventName) - \(session.remainingLabel)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(theme.primaryDark)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(theme.primaryLight, in: Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }
}

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.86), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
