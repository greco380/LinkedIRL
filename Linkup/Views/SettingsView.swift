import SwiftUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkupTheme) private var theme
    @State private var linkedInURL = ""
    @State private var linkedInStage: String?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsHeader {
                    dismiss()
                }

                SettingsSection(title: "Account") {
                    HStack(spacing: 12) {
                        AvatarView(
                            initials: store.account?.initials ?? "JG",
                            colorHex: "FF5E3A",
                            size: 38,
                            pictureURL: store.account?.linkedInPictureURL
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.account?.displayName ?? "Josh Greco")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(store.account?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                }

                LinkedInSettings(linkedInURL: $linkedInURL, linkedInStage: $linkedInStage)

                SettingsSection(title: "Appearance") {
                    SettingsRow(icon: "circle.lefthalf.filled", label: "Theme") {
                        Picker("Theme", selection: Binding(
                            get: { store.settings.theme },
                            set: { store.setTheme($0) }
                        )) {
                            Text("Light").tag(ThemeChoice.light)
                            Text("Dark").tag(ThemeChoice.dark)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 148)
                    }
                }

                SettingsSection(title: "Sharing") {
                    SettingsRow(icon: "timer", label: "Default duration") {
                        HStack(spacing: 8) {
                            Button {
                                store.updateDefaultShareHours(by: -1)
                            } label: {
                                Image(systemName: "minus")
                            }
                            Text("\(store.settings.defaultShareHours)h")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 34)
                            Button {
                                store.updateDefaultShareHours(by: 1)
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                        .foregroundStyle(theme.primary)
                    }

                    Divider().background(theme.rowDivider)

                    SettingsRow(icon: "person.2.fill", label: "Who can see you") {
                        Picker("Audience", selection: Binding(
                            get: { store.settings.audience },
                            set: { store.setAudience($0) }
                        )) {
                            Text("1st").tag(Audience.firstDegree)
                            Text("1st + 2nd").tag(Audience.firstAndSecondDegree)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 158)
                    }

                    Divider().background(theme.rowDivider)

                    SettingsToggleRow(
                        icon: "location.badge.plus",
                        label: "Auto-share at known events",
                        isOn: Binding(get: { store.settings.autoShareKnownEvents }, set: { store.setToggle(\.autoShareKnownEvents, to: $0) })
                    )
                }

                SettingsSection(title: "Notifications") {
                    SettingsToggleRow(
                        icon: "person.crop.circle.badge.checkmark",
                        label: "Connection arrives at my event",
                        isOn: Binding(get: { store.settings.notifNewSharer }, set: { store.setToggle(\.notifNewSharer, to: $0) })
                    )
                    Divider().background(theme.rowDivider)
                    SettingsToggleRow(
                        icon: "message.fill",
                        label: "New messages",
                        isOn: Binding(get: { store.settings.notifNewMessage }, set: { store.setToggle(\.notifNewMessage, to: $0) })
                    )
                    Divider().background(theme.rowDivider)
                    SettingsToggleRow(
                        icon: "clock.badge.exclamationmark",
                        label: "Sharing about to expire",
                        isOn: Binding(get: { store.settings.notifExpiring }, set: { store.setToggle(\.notifExpiring, to: $0) })
                    )
                }

                QRShareSettings()

                LegalSettings()

                SettingsSection(title: "Account actions") {
                    Button {
                        dismiss()
                        store.signOut()
                    } label: {
                        Text("Sign out")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: 0xFF3B30))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .buttonStyle(.plain)

                    Divider().background(theme.rowDivider)

                    // Delete account — Apple guideline 5.1.1(v) requires this
                    // for any app that creates an account in-app. Destructive
                    // styling + confirmation alert before anything is wiped.
                    Button {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack {
                            Text(isDeletingAccount ? "Deleting account..." : "Delete account")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(hex: 0xFF3B30))
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount)
                }

                Button("Reset prototype") {
                    dismiss()
                    store.resetPrototype()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .alert("Delete account?", isPresented: $showDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    await store.deleteAccount()
                    isDeletingAccount = false
                    dismiss()
                }
            }
        } message: {
            Text("This permanently deletes your Linkup account, your LinkedIn import, your share sessions, and all chats. This cannot be undone.")
        }
    }
}


private struct SettingsHeader: View {
    @Environment(\.linkupTheme) private var theme
    var done: () -> Void

    var body: some View {
        ZStack {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            HStack {
                Button(action: done) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(theme.primary)
                Spacer()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }
}

private struct LinkedInSettings: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @Binding var linkedInURL: String
    @Binding var linkedInStage: String?
    @State private var showArchiveGuide = false
    @State private var showConnectionImporter = false

    var body: some View {
        SettingsSection(title: "LinkedIn") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("in")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0x0A66C2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.account?.linkedInConnected == true ? "Connected" : "Not connected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                }

                if let linkedInStage {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(linkedInStage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.account?.linkedInConnected == true {
                            profileSummary
                        } else {
                            TextField("linkedin.com/in/yourname", text: $linkedInURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            runAPIImport()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                Text(store.linkedInNetworkDatabase == nil ? "Connect with LinkedIn" : "Refresh from LinkedIn")
                                Spacer()
                                Text("API")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: 0x0A66C2), in: Capsule())
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .padding(12)
                            .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showArchiveGuide = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.and.arrow.down.fill")
                                Text(store.linkedInNetworkDatabase == nil ? "Import LinkedIn archive" : "Replace LinkedIn archive")
                                Spacer()
                                Text("Archive")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.primaryDark)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(theme.primaryLight, in: Capsule())
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .padding(12)
                            .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            if store.account?.linkedInConnected != true {
                                Button("Save profile") {
                                    saveProfile()
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 42)
                                .background(Color(hex: 0x0A66C2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            if store.account?.linkedInConnected == true {
                                Button("Disconnect") {
                                    store.disconnectLinkedIn()
                                }
                                .buttonStyle(.bordered)
                                .foregroundStyle(Color(hex: 0xFF3B30))
                            }
                        }

                        if let preview = store.linkedInNetworkDatabase?.connections.prefix(3), !preview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(preview)) { connection in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(connection.displayName.isEmpty ? connection.profileURL : connection.displayName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(theme.textPrimary)
                                            Text([connection.position, connection.company].compactMap { $0 }.joined(separator: " at "))
                                                .font(.caption2)
                                                .foregroundStyle(theme.textSecondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(12)
                            .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $showArchiveGuide) {
            LinkedInArchiveGuideSheet(canImport: canImport) {
                showArchiveGuide = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showConnectionImporter = true
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $showConnectionImporter,
            allowedContentTypes: linkedInImportContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                runArchiveImport(url)
            case .failure(let error):
                store.showToast(error.localizedDescription)
            }
        }
    }

    // Importing only requires being signed in. We used to also require a saved
    // profile URL, but that field lives on the Settings screen *behind* this
    // sheet, so it left the "Choose file" button greyed out with no way to fix
    // it from here. A profile URL is now optional (it sharpens connection
    // matching, but name-matching works without it).
    private var canImport: Bool {
        store.account != nil
    }

    private var linkedInImportContentTypes: [UTType] {
        [
            .commaSeparatedText,
            .plainText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            UTType(filenameExtension: "zip") ?? .data
        ]
    }

    private var subtitle: String {
        guard let account = store.account else { return "Connect to import your network" }
        guard account.linkedInConnected else { return "Save your profile URL, then import your LinkedIn archive" }
        if account.linkedInConnectionCount == 0 {
            return "Profile saved - import your LinkedIn archive"
        }
        return "\(account.linkedInConnectionCount) connections in local database"
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.account?.linkedInURL ?? store.account?.linkedInMemberID ?? "LinkedIn account linked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text("Network records are stored under this Linkup account.")
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func saveProfile() {
        do {
            try store.saveLinkedInProfile(url: linkedInURL)
        } catch {
            store.showToast(error.localizedDescription)
        }
    }

    private func runAPIImport() {
        Task {
            linkedInStage = "Opening LinkedIn..."
            do {
                try await store.importLinkedInConnectionsFromAPI()
            } catch {
                store.showToast(error.localizedDescription)
            }
            linkedInStage = nil
        }
    }

    private func runArchiveImport(_ url: URL) {
        Task {
            let stages = ["Reading LinkedIn export...", "Normalizing profile links...", "Saving network database..."]
            for stage in stages {
                linkedInStage = stage
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            do {
                // Attach the import to a claimed profile when the user provided
                // one, but don't block the import if they didn't — an empty/invalid
                // URL must not stop the CSV from loading.
                if store.account?.linkedInConnected != true {
                    let profile = linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !profile.isEmpty {
                        try? store.saveLinkedInProfile(url: profile)
                    }
                }
                try store.importLinkedInConnections(from: url, source: .linkedinArchive)
            } catch {
                store.showToast(error.localizedDescription)
            }
            linkedInStage = nil
        }
    }
}

private struct LinkedInArchiveGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkupTheme) private var theme
    var canImport: Bool
    var chooseFile: () -> Void

    private let dataExportURL = URL(string: "https://www.linkedin.com/mypreferences/d/download-my-data")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Import LinkedIn archive")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(theme.bgSecondary, in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                ArchiveStep(number: 1, title: "Open LinkedIn's data page", detail: "Choose the Connections data export for your account.")
                ArchiveStep(number: 2, title: "Wait for LinkedIn's download", detail: "LinkedIn can take minutes or several hours before the archive is ready.")
                ArchiveStep(number: 3, title: "Import the connections file", detail: "Open the archive, then select Connections.csv from the downloaded LinkedIn data.")
            }

            VStack(spacing: 10) {
                Link(destination: dataExportURL) {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Open LinkedIn data page")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color(hex: 0x0A66C2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    chooseFile()
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Choose downloaded file")
                        Spacer()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canImport ? theme.textPrimary : theme.textTertiary)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canImport)
            }

            if !canImport {
                Text("Enter your LinkedIn profile URL first so Linkup can attach the import to your claimed profile.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(theme.bg.ignoresSafeArea())
    }
}

private struct ArchiveStep: View {
    @Environment(\.linkupTheme) private var theme
    var number: Int
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(theme.primary, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct LegalSettings: View {
    @Environment(\.linkupTheme) private var theme

    private static let fallbackPrivacy = "https://linkup.app/privacy"
    private static let fallbackTerms = "https://linkup.app/terms"

    private var privacyURL: URL {
        Self.url(forInfoKey: "LINKUP_PRIVACY_URL", fallback: Self.fallbackPrivacy)
    }

    private var termsURL: URL {
        Self.url(forInfoKey: "LINKUP_TERMS_URL", fallback: Self.fallbackTerms)
    }

    var body: some View {
        SettingsSection(title: "Legal") {
            Link(destination: privacyURL) {
                legalRow(icon: "hand.raised.fill", label: "Privacy Policy")
            }
            .buttonStyle(.plain)

            Divider().background(theme.rowDivider)

            Link(destination: termsURL) {
                legalRow(icon: "doc.text.fill", label: "Terms of Service")
            }
            .buttonStyle(.plain)
        }
    }

    private func legalRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primary)
                .frame(width: 32, height: 32)
                .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private static func url(forInfoKey key: String, fallback: String) -> URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !value.contains("#######"),
           let parsed = URL(string: value) {
            return parsed
        }
        return URL(string: fallback)!
    }
}

private enum QRTarget: String, CaseIterable {
    case app = "Download"
    case linkedin = "LinkedIn"
}

private struct QRShareSettings: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @State private var target: QRTarget = .app

    private var qrURL: String {
        switch target {
        case .app:
            return "https://linkup.app/download"
        case .linkedin:
            return store.account?.linkedInURL ?? "https://www.linkedin.com"
        }
    }

    var body: some View {
        SettingsSection(title: "QR code") {
            VStack(alignment: .leading, spacing: 14) {
                SettingsRow(icon: "qrcode", label: "Share") {
                    Picker("QR target", selection: $target) {
                        ForEach(QRTarget.allCases, id: \.self) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 178)
                }

                HStack(spacing: 14) {
                    QRCodeImage(value: qrURL)
                        .frame(width: 112, height: 112)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(target == .app ? "Download Linkup" : "Connect on LinkedIn")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(qrURL)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct QRCodeImage: View {
    var value: String
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = makeImage() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code")
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.black)
                .accessibilityLabel("QR code unavailable")
        }
    }

    private func makeImage() -> UIImage? {
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.linkupTheme) private var theme
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    @Environment(\.linkupTheme) private var theme
    var icon: String
    var label: String
    var trailing: Trailing

    init(icon: String, label: String, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primary)
                .frame(width: 32, height: 32)
                .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            trailing
        }
        .padding(14)
    }
}

private struct SettingsToggleRow: View {
    @Environment(\.linkupTheme) private var theme
    var icon: String
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(icon: icon, label: label) {
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .tint(theme.primary)
        }
    }
}
