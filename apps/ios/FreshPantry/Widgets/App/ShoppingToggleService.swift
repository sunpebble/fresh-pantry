import Foundation
import os
import SwiftData

/// 小组件交互勾选的可测核心。翻转共享 store 里某购物项的 `isChecked`,并在有
/// 家庭作用域时直接记一条 `.toggleChecked` outbox 操作(刻意不经 `SyncWriter`,
/// 那会把 `SyncCoordinator`→Supabase 网络层拖进 widget)。app 下次前台用既有
/// `SyncCoordinator` 推送这条 op。完整对齐 `ShoppingStore.toggleChecked` 的写口径。
enum ShoppingToggleService {
    /// 返回是否翻转成功(目标行不存在 / 写失败 → false)。
    @discardableResult
    static func toggle(container: ModelContainer, householdID: String, itemID: String, clientID: String, now: Date) async -> Bool {
        let shopping = ShoppingRepository(modelContainer: container)
        guard let all = try? await shopping.loadAllFor(householdID),
              let prior = all.first(where: { $0.id == itemID }) else { return false }

        let toggled = prior.copyWith(isChecked: !prior.isChecked)
        guard (try? await shopping.updateRow(householdID, toggled)) == true else { return false }

        // 仅本地(无家庭)→ 已持久化,无需 outbox(无远程可推)。
        guard !householdID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }

        let outbox = SyncOutboxRepository(modelContainer: container)
        let op = SyncOperation(
            id: UUID().uuidString.lowercased(),
            householdId: householdID,
            entityType: .shoppingItem,
            entityId: toggled.id,
            operation: .toggleChecked,
            patch: ["isChecked": .bool(toggled.isChecked)],
            baseVersion: prior.remoteVersion,
            clientId: clientID,
            createdAt: now
        )
        do {
            try await outbox.enqueue(op)
        } catch {
            // 与 SyncWriter 一致:outbox 写失败意味着这条翻转在该行被重新编辑前
            // 永不同步(本地已改、远程不知)。本地翻转已成功,故仍返 true,但记一条
            // error 供 Console 排查这种静默漂移。
            Logger(subsystem: "com.sunpebble.freshpantry", category: "widget")
                .error("widget shopping toggle outbox enqueue failed for \(toggled.id, privacy: .public): \(error.localizedDescription, privacy: .public) — will not sync until re-edited")
        }
        return true
    }
}
