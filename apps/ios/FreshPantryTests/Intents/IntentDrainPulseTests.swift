import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The drain → foreground-refresh pulse: `IntentAddDrainer` posts
/// `.intentDidDrainShoppingAdd` ONLY after a drain actually wrote rows, so the
/// shopping tab (a different `ShoppingStore` instance) reloads exactly when
/// there is something new to show. Each test uses its own `NotificationCenter`
/// so parallel tests' drains can't cross-pollute the observation.
@MainActor
struct IntentDrainPulseTests {
    /// Thread-safe pulse counter (the block observer must be `@Sendable`).
    private final class PulseCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    private func makeQueue() -> IntentPendingAddQueue {
        IntentPendingAddQueue(defaults: UserDefaults(suiteName: "test.drainPulse.\(UUID().uuidString)")!)
    }

    @Test func drainPulsesAfterWritingRows() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        let queue = makeQueue()
        queue.enqueue("牛奶")
        queue.enqueue("鸡蛋")

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .intentDidDrainShoppingAdd, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue, center: center)

        #expect(counter.value == 1) // one pulse per drain, not per name
        #expect(Set(try await dependencies.shoppingRepository.loadAllFor("home").map(\.name)) == ["牛奶", "鸡蛋"])
    }

    @Test func duplicateOnlyDrainDoesNotPulse() async throws {
        // The name was already on the list → consumed without a write, so a
        // reload would show nothing new; the pulse must stay quiet.
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        try await dependencies.shoppingRepository.saveItems("home", [
            ShoppingItem(id: "s1", name: "牛奶", detail: "", category: FoodCategories.other),
        ])
        let queue = makeQueue()
        queue.enqueue("牛奶")

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .intentDidDrainShoppingAdd, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue, center: center)

        #expect(counter.value == 0)
        #expect(queue.peek() == []) // still consumed (already-present == satisfied)
    }

    @Test func emptyQueueDrainDoesNotPulse() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")

        let center = NotificationCenter()
        let counter = PulseCounter()
        let token = center.addObserver(forName: .intentDidDrainShoppingAdd, object: nil, queue: nil) { _ in
            counter.bump()
        }
        defer { center.removeObserver(token) }

        await IntentAddDrainer.drain(dependencies: dependencies, queue: makeQueue(), center: center)

        #expect(counter.value == 0)
    }
}
