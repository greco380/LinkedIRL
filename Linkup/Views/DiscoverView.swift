import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @State private var showShareSheet = false
    @State private var selectedProfile: ConnectionProfile?

    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HeaderView(title: "Discover", openSettings: openSettings)

            VenueMapView(connections: store.visibleConnections) { connection in
                selectedProfile = connection
            }
            .frame(maxHeight: store.shareSession == nil ? 405 : 360)
            .padding(.horizontal, 22)

            if let session = store.shareSession {
                SharingListView(session: session, selectedProfile: $selectedProfile)
            } else {
                ConnectCTA {
                    showShareSheet = true
                }
                .padding(.horizontal, 22)
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareLocationSheet()
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileSheet(connection: profile)
        }
    }
}

private struct ConnectCTA: View {
    @Environment(\.linkupTheme) private var theme
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Share your location to see which of your network are at the event with you.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineSpacing(3)
                }
            }

            Button(action: action) {
                Text("Share my location")
                    .font(.headline)
                    .foregroundStyle(theme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [theme.primary, theme.primaryGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: theme.primary.opacity(0.22), radius: 24, y: 14)
    }
}

private struct SharingListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    var session: ShareSession
    @Binding var selectedProfile: ConnectionProfile?
    @State private var openRowID: String?

    var body: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    Text("\(store.visibleConnections.count) at \(session.eventName)")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("Stop sharing") {
                        store.stopSharing()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visibleConnections) { connection in
                            ConnectionRow(connection: connection, openRowID: $openRowID) {
                                selectedProfile = connection
                            }
                        }
                    }
                }
                .frame(maxHeight: 238)
            }
        }
        .padding(.horizontal, 22)
    }
}

struct ConnectionRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    var connection: ConnectionProfile
    @Binding var openRowID: String?
    var onTap: () -> Void

    var body: some View {
        SwipeActionRow(
            id: connection.id,
            openRowID: $openRowID,
            minHeight: 64,
            onTap: onTap,
            onMute: { store.mute(connection) },
            onBlock: { store.block(connection) }
        ) {
            HStack(spacing: 12) {
                AvatarView(initials: connection.initials, colorHex: connection.colorHex)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(connection.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if store.isMuted(connection) {
                            Image(systemName: "bell.slash.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    Text(connection.headline)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.rowDivider)
                .frame(height: 1)
                .padding(.leading, 72)
        }
    }
}

struct VenueMapView: View {
    @Environment(\.linkupTheme) private var theme
    var connections: [ConnectionProfile]
    var onPinTap: (ConnectionProfile) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [theme.mapBg1, theme.mapBg2], startPoint: .topLeading, endPoint: .bottomTrailing))

                venueFloorPlan
                    .padding(18)

                label("Hall A", x: 0.16, y: 0.16, width: width, height: height)
                label("Main Stage", x: 0.49, y: 0.16, width: width, height: height)
                label("Hall B", x: 0.82, y: 0.16, width: width, height: height)
                label("Demo Floor", x: 0.50, y: 0.53, width: width, height: height)
                label("Sponsor Lounge", x: 0.50, y: 0.89, width: width, height: height)

                YouPin()
                    .position(x: width * 0.50, y: height * 0.62)

                ForEach(connections) { connection in
                    Button {
                        onPinTap(connection)
                    } label: {
                        VStack(spacing: 0) {
                            AvatarView(initials: connection.initials, colorHex: connection.colorHex, size: 36)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                            Triangle()
                                .fill(Color(hexString: connection.colorHex))
                                .frame(width: 12, height: 8)
                                .offset(y: -1)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: width * connection.mapX, y: height * connection.mapY)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
    }

    private var venueFloorPlan: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let xs: [CGFloat] = [0.16, 0.50, 0.84]
            let ys: [CGFloat] = [0.16, 0.50, 0.84]
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.34))
                    path.addLine(to: CGPoint(x: w, y: h * 0.34))
                    path.move(to: CGPoint(x: 0, y: h * 0.66))
                    path.addLine(to: CGPoint(x: w, y: h * 0.66))
                    path.move(to: CGPoint(x: w * 0.34, y: 0))
                    path.addLine(to: CGPoint(x: w * 0.34, y: h))
                    path.move(to: CGPoint(x: w * 0.66, y: 0))
                    path.addLine(to: CGPoint(x: w * 0.66, y: h))
                }
                .stroke(theme.mapHall, style: StrokeStyle(lineWidth: 24, lineCap: .round))

                ForEach(0..<9, id: \.self) { index in
                    let col = index % 3
                    let row = index / 3
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == 4 ? theme.mapBoothAlt : theme.mapBooth)
                        .frame(width: col == 1 ? w * 0.21 : w * 0.27, height: row == 1 ? h * 0.20 : h * 0.25)
                        .position(x: xs[col] * w, y: ys[row] * h)
                }
            }
        }
    }

    private func label(_ text: String, x: Double, y: Double, width: CGFloat, height: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(theme.mapLabel)
            .position(x: width * x, y: height * y)
    }
}

private struct YouPin: View {
    @Environment(\.linkupTheme) private var theme
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.youPin.opacity(0.18), lineWidth: 18)
                .frame(width: pulse ? 58 : 30, height: pulse ? 58 : 30)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(theme.youPin)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 4))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
