import SwiftUI

/// AI 文本解析 sheet: paste a free-form food list, tap 解析, and the AI parses it
/// into reviewable `IntakeProposal`s pushed to the shared `IntakeReviewView`.
///
/// Gated on a configured AI provider — when unconfigured it shows a friendly
/// "去设置配置 AI" note instead of the editor (mirrors the local-only patterns).
struct PasteImportView: View {
    let aiSettings: AiSettings
    /// Called after a successful apply so the presenter can refresh + dismiss the
    /// whole add flow.
    var onApplied: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: PasteImportStore?
    @State private var reviewRoute: ReviewRoute?
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if aiSettings.isConfigured {
                    editor
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle("AI 解析文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                if aiSettings.isConfigured, let store {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(store.isParsing ? "解析中…" : "解析") {
                            Task { await runParse(store) }
                        }
                        .font(.fkLabelLarge)
                        .disabled(!store.canParse)
                    }
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                IntakeReviewView(proposals: route.proposals, title: "确认入库") { _ in
                    onApplied()
                    dismiss()
                }
            }
        }
        .task {
            if store == nil {
                store = PasteImportStore(
                    aiSettings: aiSettings,
                    inventoryRepository: dependencies.inventoryRepository,
                    householdID: dependencies.householdID
                )
            }
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: FkSpacing.lg) {
                    Text("粘贴一段食材清单,AI 会拆成结构化条目供你审核入库。")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)

                    textEditor(store)

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
                    Text("如:牛奶 2 盒、鸡蛋一打、西红柿 3 个…")
                        .font(.fkBodyLarge)
                        .foregroundStyle(Color.fkOnSurfaceVariant.opacity(0.6))
                        .padding(.horizontal, FkSpacing.sm + 5)
                        .padding(.vertical, FkSpacing.sm + 8)
                        .allowsHitTesting(false)
                }
            }
            .focused($editorFocused)
    }

    private var notConfigured: some View {
        FkEmptyState(
            systemImage: "wand.and.stars",
            title: "请先在设置中配置 AI",
            message: "在 设置 › AI 助手 填写 Base URL / API Key / 模型 后,即可粘贴文本自动解析食材。"
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

/// A compact inline notice row (icon + message) for surfacing parse / AI errors
/// inside the paste-import sheet.
private struct FkInlineNotice: View {
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
