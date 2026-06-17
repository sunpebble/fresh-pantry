import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The widget-toggle drain → foreground-refresh pulse: `WidgetPendingToggleDrainer`
/// posts `.widgetDidDrainShoppingToggle` ONLY after a drain actually flipped a row,
/// so the 购物 list (and the 首页 购物 tile) — each a DIFFERENT `ShoppingStore`
/// instance — reload exactly when a cross-process widget toggle changed something.
/// Without the pulse the app keeps its pre-toggle snapshot (the "小组件勾选后 App 没
/// 跟随变更" bug). The exact mirror of `IntentDrainPulseTests`; each test uses its
/// own `NotificationCenter` so parallel drains can't cross-pollute the observation,
/// and injects `pending` so it never touches the shared App Group queue file.
@MainActor
struct WidgetDrainPulseTests {
    /// Thread-safe pulse counter (the block observer must be `@Sendable`).
    private final class PulseCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @Test func drainPulsesAfterFlippingRow() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        try await dependencies.shoppingRepository.saveItems("home", [
            ShoppingItem(id: "s1", name: "牛奶", detail: "", category: FoodCategories.other, isChecked: false),
        ])

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .widgetDidDrainShoppingToggle, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await WidgetPendingToggleDrainer.drain(dependencies: dependencies, pending: ["s1"], center: center)

        #expect(counter.value == 1) // one pulse per drain, not per id
        let rows = try await dependencies.shoppingRepository.loadAllFor("home")
        #expect(rows.first(where: { $0.id == "s1" })?.isChecked == true)
    }

    @Test func missingRowDrainDoesNotPulse() async throws {
        // The queued id no longer matches any row (deleted before foreground) →
        // `ShoppingToggleService.toggle` writes nothing, so a reload would show
        // nothing new; the pulse must stay quiet.
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .widgetDidDrainShoppingToggle, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await WidgetPendingToggleDrainer.drain(dependencies: dependencies, pending: ["ghost"], center: center)

        #expect(counter.value == 0)
    }

    @Test func emptyDrainDoesNotPulse() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .widgetDidDrainShoppingToggle, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await WidgetPendingToggleDrainer.drain(dependencies: dependencies, pending: [], center: center)

        #expect(counter.value == 0)
    }
}
