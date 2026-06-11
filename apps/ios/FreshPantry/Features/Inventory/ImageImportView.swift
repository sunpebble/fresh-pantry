import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// AI 图片识别 sheet: pick a photo (groceries / a fridge) from the library, the
/// AI vision model recognizes the ingredients, and they are parsed into
/// reviewable `IntakeProposal`s pushed to the shared `IntakeReviewView`.
///
/// Shares the EXACT draft → proposal → review machinery with the text paste-import
/// flow via `PasteImportStore.parseImage`, so the apply + sync-enqueue logic is
/// never duplicated. Gated on a configured AI provider — when unconfigured it
/// shows the same friendly "去设置配置 AI" note as the text path.
///
/// Uses `PhotosUI.PhotosPicker` (out-of-process `PHPickerViewController`), so it
/// works in the simulator and needs NO `NSPhotoLibraryUsageDescription` key.
struct ImageImportView: View {
    let aiSettings: AiSettings
    /// Called after a successful apply so the presenter can refresh + dismiss the
    /// whole add flow.
    var onApplied: () -> Void = {}

    /// Longest edge (in pixels) the picked image is downscaled to before base64 —
    /// bounds the payload so the data URL stays a reasonable size for the request.
    private static let maxImageDimension = 1024

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var store: PasteImportStore?
    @State private var reviewRoute: ReviewRoute?
    @State private var pickedItem: PhotosPickerItem?
    @State private var loadError: String?

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
            .navigationTitle("拍照/相册识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(store?.isParsing == true)
                }
            }
            .overlay {
                if store?.isParsing == true {
                    ImageImportBusyOverlay()
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

    // MARK: Picker

    @ViewBuilder
    private var picker: some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: FkSpacing.lg) {
                    Text("从相册选择一张食材或冰箱照片,AI 会识别出可入库的食材供你审核。")
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
                    .disabled(store.isParsing)

                    if let message = loadError ?? store.errorMessage {
                        FkImageImportNotice(systemImage: "exclamationmark.triangle", message: message)
                    }
                }
                .padding(FkSpacing.lg)
            }
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "photo.on.rectangle.angled")
            Text("选择照片")
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
            systemImage: "wand.and.stars",
            title: "请先在设置中配置 AI",
            message: "在 设置 › AI 助手 填写 Base URL / API Key / 模型 后,即可拍照或选图自动识别食材。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// Loads the picked photo, downscales it off-main, and runs the AI vision
    /// parse → review push. Resets the picker selection at the end (success OR
    /// failure) so the SAME photo can be re-picked after a retry — an identical
    /// pick never re-fires `onChange` (mirrors the add form's expiry-photo picker).
    private func handlePicked(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let store else { return }
        loadError = nil

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            loadError = "读取照片失败:\(error.localizedDescription)"
            return
        }
        guard let data, !data.isEmpty else {
            loadError = "读取照片失败,请重试。"
            return
        }

        // Downscale/recompress off the main actor so a large image never blocks UI.
        let maxDimension = Self.maxImageDimension
        let jpeg = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value
        guard let jpeg else {
            loadError = "无法处理该照片,请换一张重试。"
            return
        }

        await store.parseImage(jpeg)
        if let proposals = store.proposals {
            reviewRoute = ReviewRoute(proposals: proposals)
            store.consumeProposals()
        }
    }
}

/// Downscales + re-encodes an image to bounded JPEG bytes using ImageIO. Keeps the
/// base64 payload small (and strips orientation/metadata) before it is sent to the
/// vision model. Pure value type so it can run off the main actor.
enum ImageDownscaler {
    /// Returns JPEG `Data` whose longest edge is at most `maxDimension` pixels, or
    /// nil if the input is not a decodable image. Up-scaling is avoided
    /// (`kCGImageSourceThumbnailMaxPixelSize` only shrinks when the source is
    /// larger; a smaller source is re-encoded as-is via the always-create flag).
    static func jpegData(from data: Data, maxDimension: Int, quality: CGFloat = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let destinationOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, thumbnail, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Dimmed busy overlay shown while the AI image recognition is running — blocks
/// interaction and signals progress (mirrors the recipe-import `AiImportBusyOverlay`).
private struct ImageImportBusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: FkSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text("AI 识别中…")
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
        .accessibilityLabel("AI 识别中")
    }
}

/// A compact inline notice row (icon + message) for surfacing load / AI errors
/// inside the image-import sheet.
private struct FkImageImportNotice: View {
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
