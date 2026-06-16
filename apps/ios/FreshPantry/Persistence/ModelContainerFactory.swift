import Foundation
import SwiftData

/// Builds the shared SwiftData schema + container for the local store.
///
/// The schema mirrors the Drift v5 table set: five synced entity tables, the
/// sync outbox, the add-history frequency table, and the food-details cache —
/// plus the device-local barcode-memory store (`BarcodeMemoryRecord`, NOT
/// synced; see its doc comment for the scope decision).
enum ModelContainerFactory {
    /// Every persisted `@Model` type in the app.
    static let models: [any PersistentModel.Type] = [
        InventoryItemRecord.self,
        ShoppingItemRecord.self,
        CustomRecipeRecord.self,
        MealPlanRecord.self,
        FoodLogRecord.self,
        FavoriteRecipeRecord.self,
        DietaryPreferenceRecord.self,
        ProfileRecord.self,
        SyncOutboxRecord.self,
        AddHistoryRecord.self,
        FoodDetailsCacheRecord.self,
        BarcodeMemoryRecord.self,
        CookHistoryRecord.self,
    ]

    static var schema: Schema { Schema(models) }

    /// 共享 store 的固定文件名(App Group 容器内)。
    static let storeFileName = "FreshPantry.store"

    /// App Group 容器内 store 的 URL;App Group 未授权(本地未签名 dev)时为 nil。
    static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupID)?
            .appending(path: storeFileName)
    }

    /// SwiftData 默认位置的旧 store(迁移源):`Application Support/default.store`。
    static func legacyDefaultStoreURL() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "default.store")
    }

    /// 一次性无损迁移:目标不存在、而旧 store 存在时,拷贝 `.store` / `-shm` /
    /// `-wal` 三件套到目标。目标已存在 → no-op(绝不覆盖)。拷贝失败容忍(调用方
    /// 回退旧位置打开,绝不丢数据)。纯文件操作,可注入 `fileManager` 单测。
    static func migrateStore(from legacy: URL, to target: URL, fileManager fm: FileManager = .default) {
        guard !fm.fileExists(atPath: target.path) else { return }
        guard fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: legacy.path + suffix)
            let dst = URL(fileURLWithPath: target.path + suffix)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    /// 生产容器。优先 App Group 容器(供小组件共享);若 App Group 不可用
    /// (本地未签名),回退 SwiftData 默认位置,保证 app 仍能启动。**仅主 app
    /// 调用**——它负责一次性迁移;小组件用 `makeSharedExisting()`,从不迁移。
    static func makeShared() throws -> ModelContainer {
        guard let storeURL = appGroupStoreURL() else {
            // 无 App Group 授权 → 默认位置(旧行为),小组件届时拿不到数据显示空态。
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        if let legacy = legacyDefaultStoreURL() {
            migrateStore(from: legacy, to: storeURL)
        }
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// 小组件用变体:**只在 App Group store 已存在时**打开它(从不迁移、从不新建)。
    /// 返回 nil → 小组件显示占位/空态,等用户首次启动 app 完成迁移。app 与 widget
    /// 跨进程并发读 + 单写由 SQLite WAL 兜底。
    static func makeSharedExisting() -> ModelContainer? {
        guard let storeURL = appGroupStoreURL(),
              FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try? ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory container for tests / previews (no on-disk persistence).
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
