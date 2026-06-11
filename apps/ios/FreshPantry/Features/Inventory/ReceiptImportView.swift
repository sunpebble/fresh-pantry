import PhotosUI
import SwiftUI

/// 扫小票批量入库 sheet: pick (or shoot) a shopping-receipt photo, OCR it ON-DEVICE
/// via `TextRecognizer` (no network), then feed the recognized text into the EXACT
/// same `PasteImportStore` text-parse chain the "AI 解析文本" flow uses. The receipt
/// path is deliberately just a "photo → OCR → text" prefix in front of the existing
/// parser → `IntakeReviewView` machinery, so the apply + sync-enqueue logic is never
/// duplicated.
///
/// Gated on a configured AI provider (the parse step needs the LLM) — when
/// unconfigured it shows the same friendly "去设置配置 AI" note as the other AI
/// import paths. Uses `PhotosUI.PhotosPicker` (out-of-process), so it works in the
/// simulator and needs NO `NSPhotoLibraryUsageDescription`.
struct ReceiptImportView: View {
    let aiSettings: AiSettings
    /// Called after a successful apply so the presenter can refresh + dismiss the
    /// whole add flow.
    var onApplied: () -> Void = {}

    /// Longest edge (px) the picked receipt is downscaled to before OCR. Receipts
    /// are tall + text-dense, so allow more resolution than the vision-import path
    /// to keep small print legible to Vision.
    private static let maxImageDimension = 2048

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: PasteImportStore?
    @State private var reviewRoute: ReviewRoute?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isRecognizing = false
    /// Local (pre-parse) errors: photo load / OCR failures. AI-parse errors live on
    /// `store.errorMessage` (shared with the text path).
    @State private var ocrError: String?

    var body: some View {
        NavigationStack {
            Group {
                if aiSettings.isConfigured {
                    picker
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle("扫小票入库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .overlay {
                if isBusy {
                    ReceiptImportBusyOverlay(isRecognizing: isRecognizing)
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
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await handlePicked(item) }
        }
    }

    /// Busy while either OCR or the AI parse is running — blocks dismiss + repick.
    private var isBusy: Bool { isRecognizing || store?.isParsing == true }

    // MARK: Picker

    @ViewBuilder
    private var picker: some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: FkSpacing.lg) {
                    Text("拍一张购物小票,先在本机离线识别文字,再由 AI 拆成可入库的食材供你审核。")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)

                    PhotosPicker(
                        selection: $pickedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        pickerLabel
                    }
                    .buttonStyle(.fkPressable)
                    .disabled(isBusy)

                    if let message = ocrError ?? store.errorMessage {
                        FkReceiptImportNotice(systemImage: "exclamationmark.triangle", message: message)
                    }
                }
                .padding(FkSpacing.lg)
            }
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "doc.text.viewfinder")
            Text("选择小票照片")
                .font(.fkLabelLarge)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fkOutline)
        }
        .foregroundStyle(Color.fkPrimary)
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkPrimarySoft)
        )
    }

    private var notConfigured: some View {
        FkEmptyState(
            systemImage: "doc.text.viewfinder",
            title: "请先在设置中配置 AI",
            message: "在 设置 › AI 助手 填写 Base URL / API Key / 模型 后,即可拍小票自动识别食材入库。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// photo → downscale → on-device OCR → feed recognized text into the SAME
    /// `PasteImportStore` text parse the "AI 解析文本" flow uses → push review.
    /// Failures (photo load / OCR) surface inline via `ocrError`; AI-parse failures
    /// surface via the shared `store.errorMessage`. Resets the picker selection at
    /// the end (success OR failure) so the SAME receipt can be re-picked after a
    /// retry — an identical pick never re-fires `onChange`.
    private func handlePicked(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let store, !isBusy else { return }
        ocrError = nil

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            ocrError = "读取照片失败:\(error.localizedDescription)"
            return
        }
        guard let data, !data.isEmpty else {
            ocrError = "读取照片失败,请重试。"
            return
        }

        // Downscale off the main actor so a large receipt photo never blocks UI,
        // then OCR (also off-actor inside TextRecognizer).
        isRecognizing = true
        let maxDimension = Self.maxImageDimension
        let jpeg = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value
        guard let jpeg else {
            isRecognizing = false
            ocrError = "无法处理该照片,请换一张重试。"
            return
        }

        let recognized: String
        do {
            recognized = try await TextRecognizer.recognizeReceiptText(from: jpeg)
        } catch let error as TextRecognizer.RecognizeError {
            isRecognizing = false
            ocrError = error.message
            return
        } catch {
            isRecognizing = false
            ocrError = "识别小票文字失败:\(error.localizedDescription)"
            return
        }
        isRecognizing = false

        // Hand the recognized receipt text to the EXISTING text parse path — no
        // second pipeline. Proposals flow to the shared review screen exactly like
        // the paste-import flow.
        store.text = recognized
        await store.parse()
        if let proposals = store.proposals {
            reviewRoute = ReviewRoute(proposals: proposals)
            store.consumeProposals()
        }
    }
}

/// Dimmed busy overlay shown while OCR (本机识别) or the AI parse runs — blocks
/// interaction and signals which stage is in flight (mirrors the AI import overlays).
private struct ReceiptImportBusyOverlay: View {
    let isRecognizing: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: FkSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text(isRecognizing ? "识别小票文字中…" : "AI 解析中…")
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
        .accessibilityLabel(isRecognizing ? "识别小票文字中" : "AI 解析中")
    }
}

/// A compact inline notice row (icon + message) for surfacing OCR / AI errors
/// inside the receipt-import sheet. Mirrors `FkImageImportNotice`.
private struct FkReceiptImportNotice: View {
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
