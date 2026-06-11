import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.linkupTheme) private var theme
    @State private var mode: AuthMode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""

    private enum AuthMode: String, CaseIterable {
        case signIn = "Sign in"
        case createAccount = "Create account"

        var socialVerb: String {
            switch self {
            case .signIn: "Sign in"
            case .createAccount: "Create account"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 40)

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [theme.primary, theme.primaryGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .shadow(color: theme.primary.opacity(0.25), radius: 20, y: 10)

                VStack(spacing: 8) {
                    Text(mode == .signIn ? "Welcome to Linkup" : "Create your Linkup account")
                        .font(.system(size: 31, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.textPrimary)

                    Text("Find your network at every event.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }

                Picker("Authentication mode", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(4)
                .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 12) {
                    SocialAuthButton(title: "\(mode.socialVerb) with Apple", symbol: "apple.logo", background: .black, foreground: .white) {
                        store.signInWithApple()
                    }

                    SocialAuthButton(title: "\(mode.socialVerb) with Google", symbolText: "G", background: store.settings.theme == .dark ? theme.surface : .white, foreground: theme.textPrimary, border: theme.border) {
                        store.signInWithGoogle()
                    }
                }

                HStack {
                    Rectangle().fill(theme.border).frame(height: 1)
                    Text("or")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                    Rectangle().fill(theme.border).frame(height: 1)
                }

                VStack(spacing: 12) {
                    if mode == .createAccount {
                        AuthTextField(placeholder: "Full name", text: $fullName, contentType: .name)
                    }
                    AuthTextField(placeholder: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .foregroundStyle(theme.textPrimary)
                }

                PrimaryButton(title: mode == .signIn ? "Sign in" : "Create account") {
                    if mode == .createAccount {
                        store.createEmailAccount(name: fullName, email: email, password: password)
                    } else {
                        store.signInEmail(email: email, password: password)
                    }
                }

                VStack(spacing: 8) {
                    Text("By continuing you agree to Linkup's terms and privacy policy.")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)

                    Button("Forgot password?") {
                        store.showToast("Password reset link sent")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(theme.bg.ignoresSafeArea())
    }
}

private struct AuthTextField: View {
    @Environment(\.linkupTheme) private var theme
    var placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .foregroundStyle(theme.textPrimary)
    }
}

private struct SocialAuthButton: View {
    var title: String
    var symbol: String?
    var symbolText: String?
    var background: Color
    var foreground: Color
    var border: Color = .clear
    var action: () -> Void

    init(title: String, symbol: String? = nil, symbolText: String? = nil, background: Color, foreground: Color, border: Color = .clear, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.symbolText = symbolText
        self.background = background
        self.foreground = foreground
        self.border = border
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                } else if let symbolText {
                    Text(symbolText)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
