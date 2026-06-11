import Foundation

/// Drains the `IntentPendingAddQueue` (item names captured by
/// `AddToShoppingListIntent`) through a live, fully-wired `ShoppingStore` so each
/// add lands in the CURRENT household scope with the real `syncWriter` (outbox
/// enqueue + push). This is the app-side half of the intent → app handoff that
/// keeps the add correct + synced (see `AddToShoppingListIntent`).
///
/// `@MainActor` because it builds and drives a `@MainActor ShoppingStore`. Wired
/// from `FreshPantryApp` keyed on `householdID`, so it runs only AFTER the active
/// household is resolved (a cold-start drain before sign-in would otherwise land
/// in the local-only "" scope).
extension Notification.Name {
    /// Posted by `IntentAddDrainer` after a drain actually WROTE rows
    /// (added/merged) — the foreground shopping list is a DIFFERENT
    /// `ShoppingStore` instance that knows nothing of this write, so without
    /// the pulse it keeps showing its pre-drain snapshot until a manual pull.
    static let intentDidDrainShoppingAdd = Notification.Name("fresh_pantry.intent.didDrainShoppingAdd")
}

@MainActor
enum IntentAddDrainer {
    /// Adds every queued name through a freshly-built store scoped to `householdID`
    /// (the same construction `ShoppingView` uses), then loads so dedup/merge runs.
    /// Builds the store ONLY when there's something to drain, to avoid needless work
    /// on every household change.
    static func drain(
        dependencies: AppDependencies,
        queue: IntentPendingAddQueue = IntentPendingAddQueue(),
        center: NotificationCenter = .default
    ) async {
        let names = queue.peek()
        guard !names.isEmpty else { return }

        let store = ShoppingStore(
            repository: dependencies.shoppingRepository,
            householdID: dependencies.householdID,
            syncWriter: dependencies.syncWriter
        )
        await store.load()

        // Ack on success: only remove a name from the persisted queue once it has
        // actually landed (added/merged, or already present). `addItem`'s three-
        // state outcome makes the split explicit: a `.duplicate` (already on the
        // list → the user's "add milk" intent is satisfied) is consumed, while a
        // `.failed` (read/persist error, no row written) stays QUEUED so the next
        // foreground drain retries it rather than silently dropping the Siri add
        // the user already saw confirmed — and never counts as a write.
        var consumed: [String] = []
        var didWrite = false
        for name in names {
            switch await store.addItem(name: name) {
            case .added:
                consumed.append(name)
                didWrite = true
            case .duplicate:
                consumed.append(name)
            case .failed:
                break // keep queued for the next drain
            }
        }
        queue.remove(consumed)
        // Pulse only on a real write — a duplicate-only drain changed nothing,
        // so the visible list has nothing new to show.
        if didWrite {
            center.post(name: .intentDidDrainShoppingAdd, object: nil)
        }
    }
}
