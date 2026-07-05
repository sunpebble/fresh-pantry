import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 数据备份 sub-screen: exports all local user data to a versioned JSON file and
/// restores it back. Export builds the blob via `BackupController.exportBackup()`,
/// writes it to a temp file, and offers it through `ShareLink`. Import opens a
/// `.fileImporter`, then — behind a destructive-overwrite confirmation — decodes
/// and writes via `BackupController.importBackup`. A bad file is rejected during
/// decode, so live data is never partially overwritten (parity invariant #8).
struct BackupView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var controller: BackupController?

    /// The export blob written to a temp file, ready to share. Rebuilt on demand.
    @State private var exportFile: BackupFile?
    @State private var exporting = false
    /// The in-flight export task, cancelled when the screen goes away — an export
    /// is pure read work, useless once nobody is there to share it. The import
    /// task is deliberately NOT tracked: cancelling a half-applied import would
    /// strand partially-written data, so it must run to completion.
    @State private var exportTask: Task<Void, Never>?

    @State private var importing = false
    /// The backup JSON awaiting the overwrite confirmation — sourced from EITHER a
    /// picked file OR the clipboard, so `confirmImport` has one String path.
    @State private var pendingImportText: String?
    @State private var showImportConfirm = false

    @State private var status: BackupStatus?

    var body: some View {
        Form {
            exportSection
            importSection
            if let status {
                statusSection(status)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .navigationTitle("backup.title")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.fkPrimary)
        .task {
            controller = BackupController(
                inventory: dependencies.inventoryRepository,
                foodLog: dependencies.foodLogRepository,
                shopping: dependencies.shoppingRepository,
                customRecipe: dependencies.customRecipeRepository,
                mealPlan: dependencies.mealPlanRepository,
                favorites: dependencies.favoritesStore,
                dietaryPreferences: dependencies.dietaryPreferencesStore,
                dietPreference: dependencies.dietPreferenceStore,
                reminderSettings: dependencies.reminderSettingsStore,
                syncWriter: dependencies.syncWriter,
                syncSession: dependencies.syncSession
            )
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportPick(result)
        }
        .alert("backup.importConfirm.title", isPresented: $showImportConfirm) {
            Button("backup.importConfirm.cancel", role: .cancel) { pendingImportText = nil }
            Button("backup.importConfirm.confirm", role: .destructive) { confirmImport() }
        } message: {
            Text(importConfirmMessage)
        }
        .onDisappear { exportTask?.cancel() }
    }

    /// 在家庭中导入时点明同步后果:导入不只是覆盖本机,还会经 outbox 上行覆盖
    /// 家庭共享数据(否则下一次远端 merge 会静默回滚刚导入的数据)。
    private var importConfirmMessage: String {
        let base = String(localized: "backup.importConfirm.message")
        guard !dependencies.householdID.isEmpty else { return base }
        return base + "\n\n" + String(localized: "backup.importConfirm.householdNote")
    }

    // MARK: 导出

    private var exportSection: some View {
        Section {
            if let exportFile {
                ShareLink(item: exportFile.url) {
                    actionRow(
                        systemImage: "square.and.arrow.up",
                        title: String(localized: "backup.export.share.title"),
                        subtitle: exportFile.name,
                        busy: false
                    )
                }
            } else {
                Button(action: prepareExport) {
                    actionRow(
                        systemImage: "tray.and.arrow.up",
                        title: String(localized: "backup.export.action.title"),
                        subtitle: String(localized: "backup.export.action.subtitle"),
                        busy: exporting
                    )
                }
                .disabled(exporting)
            }
            Button(action: copyExport) {
                actionRow(
                    systemImage: "doc.on.doc",
                    title: String(localized: "backup.export.copy.title"),
                    subtitle: String(localized: "backup.export.copy.subtitle"),
                    busy: exporting
                )
            }
            .disabled(exporting)
        } header: {
            Text("backup.export.header")
        } footer: {
            Text("backup.export.footer")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    private func prepareExport() {
        guard let controller else { return }
        exporting = true
        status = nil
        exportTask = Task {
            defer { exporting = false }
            do {
                let json = try await controller.exportBackup()
                guard !Task.isCancelled else { return }
                exportFile = try BackupFile.write(json)
            } catch {
                status = .failure(String(localized: "backup.export.failure"))
            }
        }
    }

    /// Copies the export JSON to the clipboard, reporting the UTF-8 byte size
    /// (matches the Flutter clipboard-export feedback).
    private func copyExport() {
        guard let controller else { return }
        exporting = true
        status = nil
        exportTask = Task {
            defer { exporting = false }
            do {
                let json = try await controller.exportBackup()
                guard !Task.isCancelled else { return }
                UIPasteboard.general.string = json
                let bytes = json.data(using: .utf8)?.count ?? 0
                status = .success(String(localized: "backup.export.copySuccess \(bytes)"))
            } catch {
                status = .failure(String(localized: "backup.export.failure"))
            }
        }
    }

    // MARK: 导入

    private var importSection: some View {
        Section {
            Button {
                importing = true
                status = nil
            } label: {
                actionRow(
                    systemImage: "tray.and.arrow.down",
                    title: String(localized: "backup.import.file.title"),
                    subtitle: String(localized: "backup.import.file.subtitle"),
                    busy: false
                )
            }
            Button(action: pasteImport) {
                actionRow(
                    systemImage: "doc.on.clipboard",
                    title: String(localized: "backup.import.paste.title"),
                    subtitle: String(localized: "backup.import.paste.subtitle"),
                    busy: false
                )
            }
        } header: {
            Text("backup.import.header")
        } footer: {
            Text("backup.import.footer")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    private func handleImportPick(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                pendingImportText = try readFile(at: url)
                showImportConfirm = true
            } catch {
                status = .failure(String(localized: "backup.import.readFailure"))
            }
        case .failure:
            status = .failure(String(localized: "backup.import.readFailure"))
        }
    }

    /// Loads backup JSON from the clipboard (the Flutter paste-import path), then
    /// routes through the same overwrite confirmation as the file import.
    private func pasteImport() {
        status = nil
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            status = .failure(String(localized: "backup.import.clipboardEmpty"))
            return
        }
        pendingImportText = text
        showImportConfirm = true
    }

    private func confirmImport() {
        guard let controller, let json = pendingImportText else { return }
        pendingImportText = nil
        status = nil
        Task {
            do {
                try await controller.importBackup(json)
                // Refresh every visible list: reuse the remote-merge pulse the
                // feature views already observe, so import results show without a
                // tab re-entry.
                dependencies.syncSession.bumpDataRevision()
                status = .success(String(localized: "backup.import.success"))
            } catch let error as BackupService.BackupError {
                status = .failure(message(for: error))
            } catch {
                status = .failure(String(localized: "backup.import.failure"))
            }
        }
    }

    /// Reads the picked file's contents, coordinating the security-scoped access a
    /// `.fileImporter` URL requires for files outside the app sandbox.
    private func readFile(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Maps the typed decode error to user-facing Chinese copy.
    private func message(for error: BackupService.BackupError) -> String {
        switch error {
        case .version: String(localized: "backup.error.unsupportedVersion")
        case .format: String(localized: "backup.error.invalidFile")
        }
    }

    // MARK: 状态

    private func statusSection(_ status: BackupStatus) -> some View {
        Section {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: status.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isSuccess ? Color.fkSuccess : Color.fkDanger)
                Text(status.text)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer()
            }
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    // MARK: Rows

    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        busy: Bool
    ) -> some View {
        HStack(spacing: FkSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                    .fill(Color.fkPrimarySoft)
                    .frame(width: FkSize.settingsIconBox, height: FkSize.settingsIconBox)
                Image(systemName: systemImage)
                    .font(.system(size: FkSize.iconSm, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(subtitle)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer()
            if busy {
                ProgressView().tint(.fkPrimary)
            }
        }
    }
}

// MARK: - Supporting types

/// A success/failure result surfaced after an export/import action.
private enum BackupStatus: Equatable {
    case success(String)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var text: String {
        switch self {
        case let .success(text), let .failure(text): text
        }
    }
}

/// A backup blob materialized to a temp file with a dated, share-friendly name.
private struct BackupFile: Equatable {
    let url: URL
    let name: String

    /// Writes `json` to a temp file named `FreshPantry-Backup-<yyyy-MM-dd>.json`.
    static func write(_ json: String) throws -> BackupFile {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "FreshPantry-Backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return BackupFile(url: url, name: name)
    }
}
