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
                            FkFormField(label: String(localized: "settings.profile.nameLabel")) {
                                FkTextFieldPill(text: $displayName, placeholder: String(localized: "settings.profile.namePlaceholder"))
                            }
                            FkFormField(label: String(localized: "settings.profile.nicknameLabel")) {
                                FkTextFieldPill(text: $nickname, placeholder: String(localized: "settings.profile.nicknamePlaceholder"))
                            }
                            if mode == .onboarding {
                                Text("settings.profile.onboardingHint")
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
            .navigationTitle(mode == .onboarding ? String(localized: "settings.profile.onboardingTitle") : String(localized: "settings.profile.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .settings {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("settings.profile.close") { dismiss() }
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
                    photoLoadError = String(localized: "settings.profile.photoLoadFailed \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        // PhotosPicker's `label` closure is inferred nonisolated, so snapshot the
        // main-actor state it needs into Sendable locals (re-read on every body
        // re-eval, so the preview stays live) and render the fallback via a
        // nonisolated static helper.
        let pickedAvatarData = pickedAvatar
        let avatarURL = store.avatarURL
        let fallbackInitial = displayName.first.map { String($0).uppercased() } ?? "?"
        return PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                if let pickedAvatarData, let ui = UIImage(data: pickedAvatarData) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let avatarURL {
                    // Edit-screen preview stays on AsyncImage: a generic CachedRemoteImage
                    // here trips the PhotosPicker label's isolation inference (the label
                    // closure is nonisolated). Every *display* surface (MemberAvatar in the
                    // settings card / profile hero, the household member list, recipe covers)
                    // is disk-cached via CachedRemoteImage; this transient editing preview
                    // is the one spot left on AsyncImage.
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Self.avatarFallbackView(fallbackInitial)
                    }
                } else {
                    Self.avatarFallbackView(fallbackInitial)
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

    // `nonisolated static`: rendered from PhotosPicker's nonisolated `label`
    // closure, so it takes the precomputed initial instead of reading @State.
    nonisolated private static func avatarFallbackView(_ initial: String) -> some View {
        ZStack {
            Color.fkPrimarySoft
            Text(initial)
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
                Text(store.isSaving ? String(localized: "settings.profile.saving") : String(localized: "settings.ai.save"))
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
