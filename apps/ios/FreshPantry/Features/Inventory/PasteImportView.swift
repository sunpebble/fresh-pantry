import SwiftUI

/// AI 文本解析 sheet: paste a free-form food list, tap 解析, and the AI parses it
/// into reviewable `IntakeProposal`s pushed to the shared `IntakeReviewView`.
///
/// Gated on the BYOK / 内置(Pro) / paywall 三态 (`AiChatAccess.resolve`): BYOK 或
/// Pro 内置通道可用时进编辑器；非 Pro 且未配置 BYOK 弹 PaywallSheet，底下保留
/// "去设置配置 AI" note（BYOK 仍是免费替代路径）。
struct PasteImportView: View {
    let aiSettings: AiSettings
    /// Called after a successful apply so the presenter can refresh + dismiss the
    /// whole add flow.
    var onApplied: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: PasteImportStore?
    @State private var reviewRoute: ReviewRoute?
    @State private var speech = SpeechTranscriber()
    /// Pro 门控：.needsPro 时弹 PaywallSheet。
    @State private var showPaywall = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                // store 存在 ⇔ 三态解析出可用通道（见 .task）。
                if store != nil {
                    editor
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle(String(localized: "inventory.import.pasteText"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                }
                if let store {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(store.isParsing ? String(localized: "inventory.pasteImport.parsing") : String(localized: "inventory.pasteImport.parse")) {
                            Task { await runParse(store) }
                        }
                        .font(.fkLabelLarge)
                        .disabled(!store.canParse)
                    }
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                IntakeReviewView(proposals: route.proposals, title: String(localized: "inventory.intakeReview.confirmTitle")) { _ in
                    onApplied()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: dependencies.proStore)
        }
        // 三态解析后再建 store；id 绑 isPro，paywall 内购买成功后自动重解析进入编辑器。
        .task(id: dependencies.proStore.isPro) {
            guard store == nil else { return }
            switch AiChatAccess.resolve(byok: aiSettings, isPro: dependencies.proStore.isPro) {
            case .byok:
                store = PasteImportStore(
                    aiSettings: aiSettings,
                    inventoryRepository: dependencies.inventoryRepository,
                    householdID: dependencies.householdID
                )
            case .builtIn:
                // 本地模式（无 Supabase 后端）内置通道不可用 → 停在 notConfigured note。
                guard let chatFn = dependencies.builtInAiChatFn() else { return }
                store = PasteImportStore(
                    aiSettings: aiSettings,
                    inventoryRepository: dependencies.inventoryRepository,
                    householdID: dependencies.householdID,
                    chatFn: chatFn
                )
            case .needsPro:
                showPaywall = true
            }
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: FkSpacing.lg) {
                    Text(String(localized: "inventory.pasteImport.subtitle"))
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)

                    textEditor(store)

                    voiceControl(store)

                    if let message = store.errorMessage {
                        FkInlineNotice(systemImage: "exclamationmark.triangle", message: message)
                    }
                }
                .padding(FkSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func textEditor(_ store: PasteImportStore) -> some View {
        @Bindable var store = store
        return TextEditor(text: $store.text)
            .font(.fkBodyLarge)
            .foregroundStyle(Color.fkOnSurface)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)
            .padding(FkSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .fill(Color.fkSurfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                    .strokeBorder(Color.fkHair, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text(String(localized: "inventory.pasteImport.placeholder"))
                        .font(.fkBodyLarge)
                        .foregroundStyle(Color.fkOnSurfaceVariant.opacity(0.6))
                        .padding(.horizontal, FkSpacing.sm + 5)
                        .padding(.vertical, FkSpacing.sm + 8)
                        .allowsHitTesting(false)
                }
            }
            .focused($editorFocused)
    }

    /// Push-to-talk dictation that fills the editor hands-free (#13). Tapping
    /// toggles recording; the live transcript shows while listening and is appended
    /// to the editor text on stop.
    @ViewBuilder
    private func voiceControl(_ store: PasteImportStore) -> some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Button {
                Task { await toggleVoice(store) }
            } label: {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(speech.isRecording ? String(localized: "inventory.voice.stop") : String(localized: "inventory.voice.start"))
                        .font(.fkLabelMedium)
                }
                .foregroundStyle(speech.isRecording ? Color.fkOnDanger : Color.fkPrimaryContainer)
                .padding(.horizontal, FkSpacing.md)
                .padding(.vertical, FkSpacing.sm)
                .background(Capsule().fill(speech.isRecording ? Color.fkDanger : Color.fkPrimarySoft))
            }
            .buttonStyle(.fkPressable)
            .accessibilityLabel(speech.isRecording ? String(localized: "inventory.voice.stopAccessibility") : String(localized: "inventory.voice.startAccessibility"))

            if speech.isRecording, !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            if let message = speech.errorMessage {
                Text(message)
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkDanger)
            }
        }
    }

    private func toggleVoice(_ store: PasteImportStore) async {
        if speech.isRecording {
            speech.stop()
            store.text = SpeechTranscriber.appendTranscript(speech.transcript, to: store.text)
        } else {
            editorFocused = false
            await speech.start()
        }
    }

    private var notConfigured: some View {
        FkEmptyState(
            systemImage: "wand.and.stars",
            title: String(localized: "inventory.ai.notConfiguredTitle"),
            message: String(localized: "inventory.pasteImport.notConfiguredMessage")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func runParse(_ store: PasteImportStore) async {
        editorFocused = false
        await store.parse()
        if let proposals = store.proposals {
            reviewRoute = ReviewRoute(proposals: proposals)
            store.consumeProposals()
        }
    }
}

/// A compact inline notice row (icon + message) for surfacing parse / AI / load
/// errors inside the import sheets. Module-internal so every import flow shares
/// this single row instead of cloning it per sheet.
struct FkInlineNotice: View {
    let systemImage: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.fkDanger)
            Text(message)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkDangerSoft)
        )
    }
}

/// Dimmed busy overlay (scrim + spinner + label) shared by every import flow —
/// `text` is the in-flight label (e.g. "AI 解析中…"); the accessibility label is
/// the same text with its trailing ellipsis dropped. Module-internal so the
/// per-sheet clones collapse to this one definition.
struct FkBusyOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: FkSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text(text)
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnSurface)
            }
            .padding(FkSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerHighest)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.hasSuffix("…") ? String(text.dropLast()) : text)
    }
}
