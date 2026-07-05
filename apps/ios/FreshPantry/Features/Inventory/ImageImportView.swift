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
/// never duplicated. Gated on the same BYOK / 内置(Pro) / paywall 三态 as the
/// text path (`AiChatAccess.resolve`) — 非 Pro 且未配置 BYOK 弹 PaywallSheet。
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
    /// Pro 门控：.needsPro 时弹 PaywallSheet。
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                // store 存在 ⇔ 三态解析出可用通道（见 .task）。
                if store != nil {
                    picker
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle(String(localized: "inventory.import.photoRecognize"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "inventory.action.cancel")) { dismiss() }
                        .disabled(store?.isParsing == true)
                }
            }
            .overlay {
                if store?.isParsing == true {
                    FkBusyOverlay(text: String(localized: "inventory.import.aiRecognizing"))
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
        // 三态解析后再建 store；id 绑 isPro，paywall 内购买成功后自动重解析进入选图。
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
                    Text(String(localized: "inventory.imageImport.subtitle"))
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
                        FkInlineNotice(systemImage: "exclamationmark.triangle", message: message)
                    }
                }
                .padding(FkSpacing.lg)
            }
        }
    }

    // `nonisolated`: the label is static chrome (no @State), so it can be read
    // from PhotosPicker's nonisolated `label` closure without an isolation warning.
    nonisolated private var pickerLabel: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "photo.on.rectangle.angled")
            Text(String(localized: "inventory.imageImport.choosePhoto"))
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
            title: String(localized: "inventory.ai.notConfiguredTitle"),
            message: String(localized: "inventory.imageImport.notConfiguredMessage")
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
            loadError = String(localized: "inventory.photo.loadFailed \(error.localizedDescription)")
            return
        }
        guard let data, !data.isEmpty else {
            loadError = String(localized: "inventory.photo.loadFailedRetry")
            return
        }

        // Downscale/recompress off the main actor so a large image never blocks UI.
        let maxDimension = Self.maxImageDimension
        let jpeg = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value
        guard let jpeg else {
            loadError = String(localized: "inventory.photo.processFailed")
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
