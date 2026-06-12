import PhotosUI
import SwiftUI

/// Profile editor, reused for both Settings (editable, dismissable) and the
/// post-login onboarding gate (`mode == .onboarding`: display name required,
/// not dismissable until saved).
struct ProfileEditView: View {
    enum Mode { case settings, onboarding }

    let store: ProfileStore
    var mode: Mode = .settings

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var nickname = ""
    @State private var pickerItem: PhotosPickerItem?
    /// Locally-picked avatar bytes (not yet uploaded) for instant preview.
    @State private var pickedAvatar: Data?
    @State private var photoLoadError: String?

    private var canSave: Bool { !displayName.trimmed.isEmpty && !store.isSaving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.xl) {
                    avatarPicker
                    FkCard {
                        VStack(alignment: .leading, spacing: FkSpacing.lg) {
                            FkFormField(label: "名称") {
                                FkTextFieldPill(text: $displayName, placeholder: "在家庭里显示的名字")
                            }
                            FkFormField(label: "昵称(可选)") {
                                FkTextFieldPill(text: $nickname, placeholder: "留空则使用名称")
                            }
                            if mode == .onboarding {
                                Text("名称会显示在家庭成员列表里,先填一个吧。")
                                    .font(.fkBodySmall)
                                    .foregroundStyle(Color.fkOnSurfaceVariant)
                            }
                        }
                    }
                    if let photoLoadError {
                        errorBanner(photoLoadError, detail: nil)
                    }
                    if let errorMessage = store.errorMessage {
                        errorBanner(errorMessage, detail: store.lastFailureDetail)
                    }
                    saveButton
                }
                .padding(FkSpacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color.fkSurface)
            .navigationTitle(mode == .onboarding ? "完善个人信息" : "个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .settings {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .tint(.fkPrimary)
            .interactiveDismissDisabled(mode == .onboarding)
        }
        .task {
            displayName = store.displayName
            nickname = store.nickname
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                photoLoadError = nil
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self) else { return }
                    pickedAvatar = compressed(data)
                } catch {
                    photoLoadError = "读取照片失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                if let pickedAvatar, let ui = UIImage(data: pickedAvatar) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let url = store.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarFallback
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.fkOutlineVariant))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fkOnPrimary)
                    .padding(6)
                    .background(Circle().fill(Color.fkPrimary))
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var avatarFallback: some View {
        ZStack {
            Color.fkPrimarySoft
            Text(displayName.first.map { String($0).uppercased() } ?? "?")
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkPrimary)
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            Task {
                await store.save(displayName: displayName, nickname: nickname, newAvatar: pickedAvatar)
                if store.errorMessage == nil, mode == .settings { dismiss() }
                // onboarding: a non-empty name flips needsProfileSetup false →
                // the root cover auto-dismisses. An offline/failed push ALSO
                // dismisses (the optimistic local name satisfies the gate); the
                // pending edit re-syncs later, so the "must have a name" intent
                // holds without trapping the user offline.
            }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                if store.isSaving { ProgressView().tint(Color.fkOnPrimary) } else { Image(systemName: "checkmark") }
                Text(store.isSaving ? "保存中…" : "保存")
            }
            .font(.fkLabelLarge)
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(canSave ? Color.fkPrimary : Color.fkOutlineVariant))
        }
        .buttonStyle(.fkPressable)
        .disabled(!canSave)
    }

    private func errorBanner(_ message: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.fkDanger)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.fkBodySmall).foregroundStyle(Color.fkDanger)
                // Raw cause, shown small/secondary so a failed save is diagnosable
                // (e.g. a storage permission rejection) instead of opaque. Selectable
                // so a tester can copy it into a report.
                if let detail {
                    Text(detail)
                        .font(.fkLabelSmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous).fill(Color.fkDangerSoft))
    }

    /// Downscale to ≤512px and JPEG-encode (~0.8) so avatars stay small in Storage.
    private func compressed(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 512
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}
