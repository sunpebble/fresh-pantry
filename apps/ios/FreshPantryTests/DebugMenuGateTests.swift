import Foundation
import Testing
@testable import FreshPantry

/// 调试菜单解锁状态:默认锁定、unlock 持久化、lock 复位。
@MainActor
struct DebugMenuGateTests {
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.debugmenugate.\(UUID().uuidString)")!
    }

    @Test func freshGateIsLocked() {
        #expect(DebugMenuGate(defaults: suite()).isUnlocked == false)
    }

    @Test func unlockPersists() {
        let defaults = suite()
        let gate = DebugMenuGate(defaults: defaults)
        gate.unlock()
        #expect(gate.isUnlocked == true)
        // 同 suite 新实例读到 unlocked。
        #expect(DebugMenuGate(defaults: defaults).isUnlocked == true)
    }

    @Test func lockResetsAndPersists() {
        let defaults = suite()
        let gate = DebugMenuGate(defaults: defaults)
        gate.unlock()
        gate.lock()
        #expect(gate.isUnlocked == false)
        #expect(DebugMenuGate(defaults: defaults).isUnlocked == false)
    }
}
