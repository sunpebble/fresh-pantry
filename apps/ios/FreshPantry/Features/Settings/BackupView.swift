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
        .navigationTitle("数据备份")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.fkPrimary)
        .task {
            controller = BackupController(
                inventory: dependencies.inventoryRepository,
                shopping: dependencies.shoppingRepository,
                customRecipe: dependencies.customRecipeRepository,
                mealPlan: dependencies.mealPlanRepository,
                aiSettings: dependencies.aiSettingsStore,
                householdID: dependencies.householdID
            )
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportPick(result)
        }
        .alert("导入将覆盖现有数据", isPresented: $showImportConfirm) {
            Button("取消", role: .cancel) { pendingImportText = nil }
            Button("覆盖导入", role: .destructive) { confirmImport() }
        } message: {
            Text("导入将覆盖本机当前的库存、采购、食谱、膳食计划等数据,确定继续?")
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        Section {
            if let exportFile {
                ShareLink(item: exportFile.url) {
                    actionRow(
                        systemImage: "square.and.arrow.up",
                        title: "分享备份文件",
                        subtitle: exportFile.name,
                        busy: false
                    )
                }
            } else {
                Button(action: prepareExport) {
                    actionRow(
                        systemImage: "tray.and.arrow.up",
                        title: "导出备份",
                        subtitle: "生成包含全部数据的 JSON 文件",
                        busy: exporting
                    )
                }
                .disabled(exporting)
            }
            Button(action: copyExport) {
                actionRow(
                    systemImage: "doc.on.doc",
                    title: "复制到剪贴板",
                    subtitle: "复制全部数据为 JSON,可粘贴到备忘录/邮件保存",
                    busy: exporting
                )
            }
            .disabled(exporting)
        } header: {
            Text("导出")
        } footer: {
            Text("备份包含库存、采购清单、自建食谱、膳食计划与 AI 配置;不含可重建的食材详情缓存。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }

    private func prepareExport() {
        guard let controller else { return }
        exporting = true
        status = nil
        Task {
            defer { exporting = false }
            do {
                let json = try await controller.exportBackup()
                exportFile = try BackupFile.write(json)
            } catch {
                status = .failure("导出失败,请重试")
            }
        }
    }

    /// Copies the export JSON to the clipboard, reporting the UTF-8 byte size
    /// (matches the Flutter clipboard-export feedback).
    private func copyExport() {
        guard let controller else { return }
        exporting = true
        status = nil
        Task {
            defer { exporting = false }
            do {
                let json = try await controller.exportBackup()
                UIPasteboard.general.string = json
                let bytes = json.data(using: .utf8)?.count ?? 0
                status = .success("已复制 \(bytes) 字节,粘贴到备忘录/邮件即可保存")
            } catch {
                status = .failure("导出失败,请重试")
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
                    title: "导入备份",
                    subtitle: "从 JSON 备份文件恢复数据",
                    busy: false
                )
            }
            Button(action: pasteImport) {
                actionRow(
                    systemImage: "doc.on.clipboard",
                    title: "从剪贴板导入",
                    subtitle: "从复制的 JSON 文本恢复数据",
                    busy: false
                )
            }
        } header: {
            Text("导入")
        } footer: {
            Text("导入会覆盖本机当前数据。无效或版本不支持的文件会被拒绝,不会破坏现有数据。")
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
                status = .failure("无法读取所选文件")
            }
        case .failure:
            status = .failure("无法读取所选文件")
        }
    }

    /// Loads backup JSON from the clipboard (the Flutter paste-import path), then
    /// routes through the same overwrite confirmation as the file import.
    private func pasteImport() {
        status = nil
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            status = .failure("剪贴板为空,请先复制备份 JSON")
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
                status = .success("已导入")
            } catch let error as BackupService.BackupError {
                status = .failure(message(for: error))
            } catch {
                status = .failure("导入失败,请重试")
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
        case .version: "不支持的备份版本"
        case .format: "备份文件无效"
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
