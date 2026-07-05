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
        .navigationTitle("账号")
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
        case .localOnly: "本地模式"
        case .signedIn: "已登录"
        default: "登录 Fresh Pantry"
        }
    }

    private var headerSubtitle: String {
        switch auth.state {
        case .localOnly: "未配置后端,当前为本地模式。数据仅保存在本机。"
        case .signedIn: "登录后即可在家庭成员间同步库存与采购。"
        case .codeSent: "我们已向你的邮箱发送了 6 位验证码。"
        default: "输入邮箱获取验证码,无需密码。"
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
                Label("登录已禁用", systemImage: "lock")
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("此版本未配置 Supabase 后端,无法登录。库存、采购与食谱仍可在本机正常使用。")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Email entry

    private var emailEntry: some View {
        VStack(spacing: FkSpacing.lg) {
            FkFormField(label: "邮箱") {
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
            primaryButton(title: "发送验证码", busyTitle: "发送中…", systemImage: "paperplane", action: send)
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
                    Text("验证码已发送至 \(email)")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                    Spacer(minLength: 0)
                }
                FkFormField(label: "验证码") {
                    TextField("6 位数字", text: $code)
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
                primaryButton(title: "验证登录", busyTitle: "验证中…", systemImage: "checkmark", action: verify)
                Button {
                    resend(email: email)
                } label: {
                    Text(resendCooldown > 0 ? "\(resendCooldown) 秒后可重新发送" : "重新发送验证码")
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
                        Text("当前账号")
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
                Text(auth.isBusy ? "退出中…" : "退出登录")
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
