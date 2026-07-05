import SwiftUI

/// AI 助手 sub-screen: an OpenAI-compatible endpoint config form (baseUrl / apiKey
/// / model / timeout) bound to the Keychain-backed `AiSettingsStore`.
///
/// Edits a local draft seeded from the store; 保存 persists the whole blob to the
/// Keychain via the store and pops — a rejected Keychain write keeps the page
/// open with an inline error instead of pretending the save landed. An
/// `isConfigured` indicator reflects the
/// CURRENTLY SAVED settings. A 测试连接 probe sends a minimal chat request against
/// the DRAFT settings (so it validates edits before saving) and reports success
/// or the mapped error.
struct AiSettingsView: View {
    let store: AiSettingsStore
    /// Pro 已解锁时未配置 BYOK 也在用内置 AI——状态行据此措辞，避免"尚未配置"误导。
    let isPro: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var baseUrl: String
    @State private var apiKey: String
    @State private var model: String
    @State private var timeoutText: String
    @State private var testResult: TestResult = .idle
    /// 保存失败（Keychain 拒写 / 编码失败）时的就地报错；nil 表示无错。
    @State private var saveErrorMessage: String?

    /// Connection-test lifecycle for the 测试连接 button.
    private enum TestResult: Equatable {
        case idle
        case testing
        case ok
        case failure(String)
    }

    init(store: AiSettingsStore, isPro: Bool) {
        self.store = store
        self.isPro = isPro
        let s = store.settings
        _baseUrl = State(initialValue: s.baseUrl)
        _apiKey = State(initialValue: s.apiKey)
        _model = State(initialValue: s.model)
        _timeoutText = State(initialValue: String(Int(s.timeout)))
    }

    /// The draft settings the form currently holds (what a test/save acts on).
    private var draftSettings: AiSettings {
        AiSettings(
            baseUrl: baseUrl.trimmed,
            apiKey: apiKey.trimmed,
            model: model.trimmed,
            timeout: TimeInterval(Int(timeoutText.trimmed) ?? 60)
        )
    }

    var body: some View {
        Form {
            Section {
                statusRow
                if let saveErrorMessage {
                    resultLabel(icon: "exclamationmark.triangle.fill", color: .fkDanger, text: saveErrorMessage)
                }
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)

            Section {
                LabeledField(label: "Base URL", text: $baseUrl, placeholder: "https://api.openai.com/v1", keyboard: .URL)
                SecureField("API Key", text: $apiKey)
                    .font(.fkBodyMedium)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledField(label: "Model", text: $model, placeholder: "gpt-4o")
                LabeledField(label: String(localized: "settings.ai.timeoutSeconds"), text: $timeoutText, placeholder: "60", keyboard: .numberPad)
            } header: {
                Text("settings.ai.connectionConfig")
            } footer: {
                Text("settings.ai.apiKeyStorageNote")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)

            Section {
                Button(action: { Task { await testConnection() } }) {
                    HStack(spacing: FkSpacing.sm) {
                        if testResult == .testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                        }
                        Text(testResult == .testing ? "settings.ai.testing" : "settings.ai.testConnection")
                            .font(.fkBodyMedium)
                    }
                    .foregroundStyle(draftSettings.isConfigured ? Color.fkPrimary : Color.fkOutline)
                }
                .disabled(!draftSettings.isConfigured || testResult == .testing)
                testResultRow
            } footer: {
                Text("settings.ai.testConnectionFooter")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .navigationTitle("settings.ai.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("settings.ai.save", action: save)
            }
        }
        .tint(.fkPrimary)
    }

    private var statusRow: some View {
        // BYOK 已配置优先（保存后覆盖内置通道）；Pro 未配置时内置 AI 已在工作，
        // 这页只是可选的自定义接入，不能显示成"尚未配置"的警示。
        let (icon, color, text): (String, Color, String) =
            store.isConfigured ? ("checkmark.seal.fill", .fkSuccess, String(localized: "settings.ai.status.configured"))
            : isPro ? ("checkmark.seal.fill", .fkSuccess, String(localized: "settings.ai.status.usingBuiltIn"))
            : ("exclamationmark.circle", .fkOutline, String(localized: "settings.ai.status.notConfigured"))
        return HStack(spacing: FkSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer()
        }
    }

    @ViewBuilder
    private var testResultRow: some View {
        switch testResult {
        case .ok:
            resultLabel(icon: "checkmark.seal.fill", color: .fkSuccess, text: String(localized: "settings.ai.connectionSuccess"))
        case let .failure(message):
            resultLabel(icon: "exclamationmark.triangle.fill", color: .fkDanger, text: message)
        case .idle, .testing:
            EmptyView()
        }
    }

    private func resultLabel(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
    }

    /// Sends a minimal chat request against the draft settings and maps the
    /// outcome (any returned content = success; an `AiError` surfaces its message).
    private func testConnection() async {
        guard draftSettings.isConfigured, testResult != .testing else { return }
        testResult = .testing
        do {
            _ = try await AiClient.chat(
                settings: draftSettings,
                messages: [.text("user", "ping")]
            )
            testResult = .ok
        } catch let error as AiError {
            testResult = .failure(error.message)
        } catch {
            testResult = .failure(String(localized: "settings.ai.connectionFailed \(error.localizedDescription)"))
        }
    }

    /// Persists the draft and pops only when the Keychain write actually landed;
    /// a rejected write surfaces in the status section and keeps the form open.
    private func save() {
        saveErrorMessage = nil
        guard store.save(draftSettings) else {
            saveErrorMessage = String(localized: "settings.ai.saveFailed")
            return
        }
        dismiss()
    }
}

/// A two-line labeled text field row for the AI config form.
private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(.fkBodyMedium)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 2)
    }
}
