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

            AdBannerView()
                .padding(.horizontal, 22)

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

                ConferenceFloorPlanView()
                    .padding(8)

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
}

/// Vector recreation of the event's expo floor plan (themed zones in the
/// corners, booth blocks, networking bars, cafe, registration/entrance).
/// Everything is laid out on a normalized [0, 1] grid so the plan scales with
/// whatever frame the map gets, and connection pins (mapX/mapY, same
/// normalized space) land on the floor correctly at any size.
private struct ConferenceFloorPlanView: View {
    @Environment(\.linkupTheme) private var theme

    private struct Zone {
        let rect: CGRect
        let leadingColor: Color
        let trailingColor: Color
        let leadingLabel: String
        let trailingLabel: String
    }

    private struct Amenity {
        let rect: CGRect
        let label: String
        var vertical = false
    }

    /// Corner topic zones, each split diagonally into two themed triangles.
    private static let zones: [Zone] = [
        Zone(
            rect: CGRect(x: 0.205, y: 0.005, width: 0.245, height: 0.135),
            leadingColor: Color(hex: 0xF5821F), trailingColor: Color(hex: 0xC97BC5),
            leadingLabel: "Data, CRM & Customer Insights",
            trailingLabel: "Digital Transformation & Leadership"
        ),
        Zone(
            rect: CGRect(x: 0.565, y: 0.005, width: 0.245, height: 0.135),
            leadingColor: Color(hex: 0x9C9C9A), trailingColor: Color(hex: 0x1A4D2E),
            leadingLabel: "Brand, Creative & Communication Strategy",
            trailingLabel: "Content, Video & Storytelling Marketing"
        ),
        Zone(
            rect: CGRect(x: 0.012, y: 0.245, width: 0.148, height: 0.220),
            leadingColor: Color(hex: 0xE8402F), trailingColor: Color(hex: 0xE8402F),
            leadingLabel: "Agentic AI & Hyper-Personalisation",
            trailingLabel: "AI-Powered Automation & Lifecycle Marketing"
        ),
        Zone(
            rect: CGRect(x: 0.842, y: 0.345, width: 0.148, height: 0.215),
            leadingColor: Color(hex: 0x6B1F7C), trailingColor: Color(hex: 0x8CC63F),
            leadingLabel: "Search, Media & Performance Advertising",
            trailingLabel: "Omnichannel Marketing, CX & Loyalty"
        ),
        Zone(
            rect: CGRect(x: 0.420, y: 0.690, width: 0.168, height: 0.165),
            leadingColor: Color(hex: 0x29ABE2), trailingColor: Color(hex: 0xEC1E79),
            leadingLabel: "Social Media & Community Marketing",
            trailingLabel: "Influencer & Creator Economy"
        ),
    ]

    /// Coral service areas (bars, cafe, registration...) from the floor plan.
    private static let amenities: [Amenity] = [
        Amenity(rect: CGRect(x: 0.915, y: 0.105, width: 0.072, height: 0.090), label: "Food Truck"),
        Amenity(rect: CGRect(x: 0.420, y: 0.265, width: 0.170, height: 0.100), label: "Networking Bar"),
        Amenity(rect: CGRect(x: 0.420, y: 0.395, width: 0.075, height: 0.075), label: "Launch Pad"),
        Amenity(rect: CGRect(x: 0.420, y: 0.495, width: 0.170, height: 0.065), label: "Networking Bar"),
        Amenity(rect: CGRect(x: 0.735, y: 0.590, width: 0.072, height: 0.070), label: "Cafe"),
        Amenity(rect: CGRect(x: 0.842, y: 0.690, width: 0.135, height: 0.165), label: "Learning Hub & Networking Zone"),
        Amenity(rect: CGRect(x: 0.085, y: 0.805, width: 0.170, height: 0.038), label: "Registration"),
        Amenity(rect: CGRect(x: 0.350, y: 0.925, width: 0.225, height: 0.060), label: "Catering"),
        Amenity(rect: CGRect(x: 0.020, y: 0.590, width: 0.034, height: 0.190), label: "Agenda Wall", vertical: true),
    ]

    /// Booth clusters. Individual booth numbers are dropped — at phone scale
    /// they'd be unreadable; the blocks preserve the hall's shape and walkways.
    private static let booths: [CGRect] = [
        // Row 1 (500s)
        CGRect(x: 0.205, y: 0.170, width: 0.075, height: 0.072),
        CGRect(x: 0.315, y: 0.170, width: 0.075, height: 0.072),
        CGRect(x: 0.425, y: 0.170, width: 0.072, height: 0.072),
        CGRect(x: 0.530, y: 0.170, width: 0.062, height: 0.072),
        CGRect(x: 0.627, y: 0.170, width: 0.070, height: 0.072),
        CGRect(x: 0.731, y: 0.170, width: 0.078, height: 0.072),
        // Row 2 (400s, flanking the upper Networking Bar)
        CGRect(x: 0.205, y: 0.265, width: 0.075, height: 0.105),
        CGRect(x: 0.315, y: 0.265, width: 0.075, height: 0.105),
        CGRect(x: 0.627, y: 0.265, width: 0.070, height: 0.105),
        CGRect(x: 0.731, y: 0.265, width: 0.078, height: 0.105),
        // Row 3 (300s, flanking the Launch Pad)
        CGRect(x: 0.205, y: 0.400, width: 0.075, height: 0.068),
        CGRect(x: 0.315, y: 0.400, width: 0.075, height: 0.068),
        CGRect(x: 0.530, y: 0.400, width: 0.062, height: 0.068),
        CGRect(x: 0.627, y: 0.400, width: 0.070, height: 0.068),
        CGRect(x: 0.731, y: 0.400, width: 0.078, height: 0.068),
        // Row 4 (200s upper, flanking the lower Networking Bar)
        CGRect(x: 0.093, y: 0.495, width: 0.073, height: 0.068),
        CGRect(x: 0.205, y: 0.495, width: 0.075, height: 0.068),
        CGRect(x: 0.315, y: 0.495, width: 0.075, height: 0.068),
        CGRect(x: 0.627, y: 0.495, width: 0.070, height: 0.068),
        CGRect(x: 0.731, y: 0.495, width: 0.078, height: 0.068),
        // Row 5 (200s lower, flanking the Cafe)
        CGRect(x: 0.093, y: 0.590, width: 0.073, height: 0.068),
        CGRect(x: 0.205, y: 0.590, width: 0.075, height: 0.068),
        CGRect(x: 0.315, y: 0.590, width: 0.075, height: 0.068),
        CGRect(x: 0.425, y: 0.590, width: 0.072, height: 0.068),
        CGRect(x: 0.530, y: 0.590, width: 0.062, height: 0.068),
        CGRect(x: 0.627, y: 0.590, width: 0.070, height: 0.068),
        CGRect(x: 0.842, y: 0.590, width: 0.075, height: 0.068),
        // Row 6 (100s / 80s, flanking the Social Media zone)
        CGRect(x: 0.093, y: 0.690, width: 0.073, height: 0.068),
        CGRect(x: 0.205, y: 0.690, width: 0.075, height: 0.068),
        CGRect(x: 0.315, y: 0.690, width: 0.075, height: 0.068),
        CGRect(x: 0.627, y: 0.690, width: 0.070, height: 0.068),
        CGRect(x: 0.731, y: 0.690, width: 0.078, height: 0.068),
        // Row 7 (50s / 60s)
        CGRect(x: 0.300, y: 0.790, width: 0.075, height: 0.068),
        CGRect(x: 0.627, y: 0.790, width: 0.070, height: 0.068),
        CGRect(x: 0.731, y: 0.790, width: 0.078, height: 0.068),
    ]

    private static let amenityFill = Color(hex: 0xF2705B)
    private static let amenityText = Color(hex: 0x1F2347)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                ForEach(Array(Self.booths.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.surface.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(theme.mapDetail.opacity(0.55), lineWidth: 0.8)
                        }
                        .frame(width: rect.width * w, height: rect.height * h)
                        .position(x: rect.midX * w, y: rect.midY * h)
                }

                ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, zone in
                    ZoneBlock(zone: zone)
                        .frame(width: zone.rect.width * w, height: zone.rect.height * h)
                        .position(x: zone.rect.midX * w, y: zone.rect.midY * h)
                }

                ForEach(Array(Self.amenities.enumerated()), id: \.offset) { _, amenity in
                    AmenityBlock(label: amenity.label, vertical: amenity.vertical)
                        .frame(width: amenity.rect.width * w, height: amenity.rect.height * h)
                        .position(x: amenity.rect.midX * w, y: amenity.rect.midY * h)
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Self.amenityFill)
                    Text("Entrance")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(theme.textPrimary)
                }
                .position(x: 0.165 * w, y: 0.90 * h)
            }
        }
    }

    /// One corner zone: two color triangles split along the top-right to
    /// bottom-left diagonal, with a label tucked into each half.
    private struct ZoneBlock: View {
        let zone: Zone

        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                ZStack {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: w, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.closeSubpath()
                    }
                    .fill(zone.leadingColor)

                    Path { path in
                        path.move(to: CGPoint(x: w, y: 0))
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.closeSubpath()
                    }
                    .fill(zone.trailingColor)

                    Path { path in
                        path.move(to: CGPoint(x: w, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: h))
                    }
                    .stroke(.white.opacity(0.9), lineWidth: 0.8)

                    zoneLabel(zone.leadingLabel)
                        .frame(width: w * 0.62, alignment: .topLeading)
                        .position(x: w * 0.34, y: h * 0.26)

                    zoneLabel(zone.trailingLabel)
                        .frame(width: w * 0.62, alignment: .bottomTrailing)
                        .position(x: w * 0.66, y: h * 0.74)
                }
            }
        }

        private func zoneLabel(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.55)
                .lineLimit(4)
        }
    }

    private struct AmenityBlock: View {
        let label: String
        let vertical: Bool

        var body: some View {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ConferenceFloorPlanView.amenityFill)
                .overlay {
                    Text(label)
                        .font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(ConferenceFloorPlanView.amenityText)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)
                        .padding(2)
                        .rotationEffect(.degrees(vertical ? -90 : 0))
                        .fixedSize(horizontal: vertical, vertical: false)
                }
        }
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
