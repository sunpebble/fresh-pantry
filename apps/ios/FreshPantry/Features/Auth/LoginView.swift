import SwiftUI

/// The 账号 screen: email-OTP login driven by `AuthService`.
///
/// Two-stage flow mirroring the Flutter `AuthGateScreen` login form:
/// email entry → "发送验证码" → 6-digit code entry → "验证登录" → signed-in state.
/// Renders four states off `AuthService.state`: localOnly (no backend),
/// signedOut, codeSent, signedIn. Pushed from Settings.
struct LoginView: View {
    @Bindable var auth: AuthService

    @State private var email = ""
    @State private var code = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, code }

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.xl) {
                header
                content
            }
            .padding(FkSpacing.lg)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fkSurface)
        .navigationTitle("auth.account.title")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.fkPrimary)
        .task { await auth.restore() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: FkSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.fkPrimarySoft)
                    .frame(width: 72, height: 72)
                Image(systemName: headerIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
            }
            Text(headerTitle)
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkOnSurface)
            Text(headerSubtitle)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(.top, FkSpacing.lg)
    }

    private var headerIcon: String {
        switch auth.state {
        case .localOnly: "wifi.slash"
        case .signedIn: "checkmark.seal.fill"
        default: "envelope.badge"
        }
    }

    private var headerTitle: String {
        switch auth.state {
        case .localOnly: String(localized: "auth.header.local.title")
        case .signedIn: String(localized: "auth.header.signedIn.title")
        default: String(localized: "auth.header.login.title")
        }
    }

    private var headerSubtitle: String {
        switch auth.state {
        case .localOnly: String(localized: "auth.header.local.subtitle")
        case .signedIn: String(localized: "auth.header.signedIn.subtitle")
        case .codeSent: String(localized: "auth.header.codeSent.subtitle")
        default: String(localized: "auth.header.login.subtitle")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .localOnly:
            localOnlyCard
        case .signedOut:
            emailEntry
        case let .codeSent(email):
            codeEntry(email: email)
        case let .signedIn(userEmail):
            signedIn(email: userEmail)
        }
        if let errorMessage = auth.errorMessage {
            errorBanner(errorMessage)
        }
    }

    // MARK: Local-only

    private var localOnlyCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                Label(String(localized: "auth.local.card.title"), systemImage: "lock")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("auth.local.card.message")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Email entry

    private var emailEntry: some View {
        VStack(spacing: FkSpacing.lg) {
            FkFormField(label: String(localized: "auth.email.label")) {
                TextField("you@example.com", text: $email)
                    .font(.fkTitleMedium)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($focusedField, equals: .email)
                    .onSubmit { send() }
                    .padding(.horizontal, FkSpacing.md)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                            .fill(Color.fkSurfaceContainer)
                    )
            }
            primaryButton(title: String(localized: "auth.button.sendCode"), busyTitle: String(localized: "auth.button.sending"), systemImage: "paperplane", action: send)
        }
    }

    // MARK: Code entry

    private func codeEntry(email: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let resendCooldown = auth.resendCooldownRemaining(at: context.date)
            VStack(spacing: FkSpacing.lg) {
                HStack(spacing: FkSpacing.sm) {
                    Image(systemName: "envelope.open")
                        .foregroundStyle(Color.fkPrimary)
                    Text(String(localized: "auth.code.sent \(email)"))
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    Spacer(minLength: 0)
                }
                FkFormField(label: String(localized: "auth.code.label")) {
                    TextField(String(localized: "auth.code.placeholder"), text: $code)
                        .font(.fkTitleMedium)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                        .padding(.horizontal, FkSpacing.md)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                                .fill(Color.fkSurfaceContainer)
                        )
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.filter(\.isNumber).prefix(6))
                        }
                }
                primaryButton(title: String(localized: "auth.button.verify"), busyTitle: String(localized: "auth.button.verifying"), systemImage: "checkmark", action: verify)
                Button {
                    resend(email: email)
                } label: {
                    Text(resendCooldown > 0 ? String(localized: "auth.code.resendAfter \(resendCooldown)") : String(localized: "auth.code.resend"))
                        .font(.fkLabelLarge)
                        .foregroundStyle(resendCooldown > 0 ? Color.fkOnSurfaceVariant : Color.fkPrimary)
                }
                .buttonStyle(.fkPressable)
                .disabled(auth.isBusy || resendCooldown > 0)
            }
        }
    }

    // MARK: Signed in

    private func signedIn(email: String) -> some View {
        VStack(spacing: FkSpacing.lg) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimary)
                            .frame(width: 44, height: 44)
                        Text(avatarLetter(email))
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("auth.currentAccount")
                            .font(.fkLabelSmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                        Text(email)
                            .font(.fkTitleSmall)
                            .foregroundStyle(Color.fkOnSurface)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await auth.signOut() }
            } label: {
                Text(auth.isBusy ? String(localized: "auth.button.signingOut") : String(localized: "auth.button.signOut"))
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.fkDangerSoft)
                    )
            }
            .buttonStyle(.fkPressable)
            .disabled(auth.isBusy)
        }
    }

    // MARK: Shared bits

    private func primaryButton(title: String, busyTitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.sm) {
                if auth.isBusy {
                    ProgressView().tint(Color.fkOnPrimary)
                } else {
                    Image(systemName: systemImage)
                }
                Text(auth.isBusy ? busyTitle : title)
            }
            .font(.fkLabelLarge)
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(auth.isBusy ? Color.fkOutlineVariant : Color.fkPrimary)
            )
        }
        .buttonStyle(.fkPressable)
        .disabled(auth.isBusy)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.fkDanger)
            Text(message)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkDanger)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                .fill(Color.fkDangerSoft)
        )
    }

    private func avatarLetter(_ email: String) -> String {
        email.first.map { String($0).uppercased() } ?? "?"
    }

    // MARK: Actions

    private func send() {
        focusedField = nil
        Task { await auth.sendCode(email: email) }
    }

    private func resend(email: String) {
        focusedField = nil
        code = ""
        Task { await auth.sendCode(email: email) }
    }

    private func verify() {
        focusedField = nil
        Task { await auth.verify(code: code) }
    }
}

#Preview("Local-only") {
    NavigationStack {
        LoginView(auth: AuthService(backend: nil))
    }
}
