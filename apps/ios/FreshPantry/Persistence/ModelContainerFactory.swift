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
        ProfileRecord.self,
        SyncOutboxRecord.self,
        AddHistoryRecord.self,
        FoodDetailsCacheRecord.self,
        BarcodeMemoryRecord.self,
        CookHistoryRecord.self,
    ]

    static var schema: Schema { Schema(models) }

    /// Production container persisting to the app's default store location.
    static func makeShared() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory container for tests / previews (no on-disk persistence).
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
