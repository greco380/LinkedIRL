import SwiftUI

struct AvatarView: View {
    var initials: String
    var colorHex: String
    var size: CGFloat = 44
    /// Optional remote image (e.g. LinkedIn picture). When present we render
    /// the photo; when nil OR when the load fails we fall back to coloured
    /// initials. Default nil so every existing call site stays the same.
    var pictureURL: URL? = nil

    var body: some View {
        Group {
            if let pictureURL {
                AsyncImage(url: pictureURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsBadge
                    }
                }
            } else {
                initialsBadge
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsBadge: some View {
        Text(initials)
            .font(.system(size: max(11, size * 0.3), weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hexString: colorHex))
    }
}

/// Sponsored banner slot. Currently renders rotating house creatives; when a
/// real ad SDK (AdMob, etc.) is added, swap the body for the SDK's banner view
/// and every placement updates at once. Height is fixed so screen layouts
/// don't shift when the creative changes.
struct AdBannerView: View {
    @Environment(\.linkupTheme) private var theme
    @Environment(\.openURL) private var openURL

    private struct Creative {
        let title: String
        let subtitle: String
        let systemImage: String
        let colorHex: UInt
        let url: URL
    }

    private static let creatives: [Creative] = [
        Creative(
            title: "Linkup Pro",
            subtitle: "See who viewed you at every event",
            systemImage: "sparkles",
            colorHex: 0x6C5CE7,
            url: URL(string: "https://linkup.app/pro")!
        ),
        Creative(
            title: "Print your event badge",
            subtitle: "Fast on-site badge printing for teams",
            systemImage: "lanyardcard.fill",
            colorHex: 0x1F8A70,
            url: URL(string: "https://linkup.app/partners")!
        ),
        Creative(
            title: "Host on Linkup",
            subtitle: "Bring live networking to your conference",
            systemImage: "megaphone.fill",
            colorHex: 0xE0A800,
            url: URL(string: "https://linkup.app/hosts")!
        ),
    ]

    @State private var creative = AdBannerView.creatives.randomElement()!

    var body: some View {
        Button {
            openURL(creative.url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: creative.systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: creative.colorHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(creative.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                    Text(creative.subtitle)
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("Ad")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(theme.textQuaternary, lineWidth: 1)
                    }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.textQuaternary)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advertisement: \(creative.title). \(creative.subtitle)")
    }
}

struct PrimaryButton: View {
    @Environment(\.linkupTheme) private var theme
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(colors: [theme.primary, theme.primaryGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: theme.primary.opacity(0.24), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
    @Environment(\.linkupTheme) private var theme
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }
}

struct SwipeActionRow<Content: View>: View {
    @Environment(\.linkupTheme) private var theme
    let id: String
    @Binding var openRowID: String?
    var minHeight: CGFloat = 64
    var onTap: () -> Void
    var onMute: () -> Void
    var onBlock: () -> Void
    var content: Content

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDraggingHorizontally = false

    private let actionWidth: CGFloat = 88
    private var revealWidth: CGFloat { actionWidth * 2 }
    private var rowAnimation: Animation? {
        isDraggingHorizontally ? nil : .spring(response: 0.28, dampingFraction: 0.86)
    }

    init(
        id: String,
        openRowID: Binding<String?>,
        minHeight: CGFloat = 64,
        onTap: @escaping () -> Void,
        onMute: @escaping () -> Void,
        onBlock: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self._openRowID = openRowID
        self.minHeight = minHeight
        self.onTap = onTap
        self.onMute = onMute
        self.onBlock = onBlock
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                actionButton(title: "Mute", systemImage: "bell.slash.fill", color: theme.slateAction) {
                    close()
                    onMute()
                }

                actionButton(title: "Block", systemImage: "hand.raised.fill", color: theme.primary) {
                    close()
                    onBlock()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(theme.surface)
                .offset(x: offset)
                .contentShape(Rectangle())
                .onTapGesture {
                    if offset < 0 {
                        close()
                    } else if openRowID != nil {
                        withAnimation {
                            openRowID = nil
                        }
                    } else {
                        onTap()
                    }
                }
                .highPriorityGesture(dragGesture)
                .animation(rowAnimation, value: offset)
        }
        .clipped()
        .onChange(of: openRowID) { _, newValue in
            if newValue != id && offset != 0 {
                withAnimation {
                    offset = 0
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)

                if !isDraggingHorizontally {
                    guard horizontal > 10, horizontal > vertical * 1.2 else { return }
                    isDraggingHorizontally = true
                    dragStartOffset = offset
                    openRowID = id
                }

                let proposedOffset = dragStartOffset + value.translation.width
                offset = min(0, max(-revealWidth, proposedOffset))
            }
            .onEnded { value in
                defer {
                    dragStartOffset = 0
                    isDraggingHorizontally = false
                }

                guard isDraggingHorizontally else { return }

                let predictedOffset = dragStartOffset + value.predictedEndTranslation.width
                if offset < -revealWidth * 0.45 || predictedOffset < -revealWidth * 0.55 {
                    open()
                } else {
                    close()
                }
            }
    }

    private func actionButton(title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(minHeight: minHeight)
            .background(color)
        }
        .buttonStyle(.plain)
    }

    private func open() {
        withAnimation {
            openRowID = id
            offset = -revealWidth
        }
    }

    private func close() {
        withAnimation {
            if openRowID == id {
                openRowID = nil
            }
            offset = 0
        }
    }
}

extension Color {
    init(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: "#", with: "")
        let value = UInt(cleaned, radix: 16) ?? 0xFF5E3A
        self.init(hex: value)
    }
}
