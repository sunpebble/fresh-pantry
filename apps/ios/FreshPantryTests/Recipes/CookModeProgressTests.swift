import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for `CookModeProgress` — the pure paging math behind Cook Mode
/// (index clamping, 上一步/下一步 boundary states, the per-page "第 x / n 步"
/// label, and the progress-bar fraction).
@MainActor
struct CookModeProgressTests {
    @Test func clampedKeepsIndexInBounds() {
        let progress = CookModeProgress(stepCount: 3)
        #expect(progress.clamped(-1) == 0)
        #expect(progress.clamped(0) == 0)
        #expect(progress.clamped(2) == 2)
        #expect(progress.clamped(99) == 2)
    }

    @Test func clampedIsZeroWhenEmpty() {
        let progress = CookModeProgress(stepCount: 0)
        #expect(progress.clamped(-5) == 0)
        #expect(progress.clamped(5) == 0)
    }

    @Test func nextAndPreviousStopAtBounds() {
        let progress = CookModeProgress(stepCount: 3)
        #expect(progress.next(after: 0) == 1)
        #expect(progress.next(after: 2) == 2) // last page: 下一步 is a no-op
        #expect(progress.previous(before: 2) == 1)
        #expect(progress.previous(before: 0) == 0) // first page: 上一步 is a no-op
    }

    @Test func boundaryFlagsDriveButtonStates() {
        let progress = CookModeProgress(stepCount: 3)
        #expect(progress.isFirst(0))
        #expect(!progress.isFirst(1))
        #expect(progress.isLast(2))
        #expect(!progress.isLast(1))
        // Out-of-range indices resolve like their clamped value.
        #expect(progress.isLast(99))
        #expect(progress.isFirst(-1))
    }

    @Test func singleStepIsBothFirstAndLast() {
        let progress = CookModeProgress(stepCount: 1)
        #expect(progress.isFirst(0))
        #expect(progress.isLast(0))
    }

    @Test func emptyStepsNeverDivideByZeroAndCountAsLast() {
        // Defensive: the entry button is hidden for step-less recipes, but the
        // math must still surface 完成 (isLast) and a zero fraction.
        let progress = CookModeProgress(stepCount: 0)
        #expect(progress.isLast(0))
        #expect(progress.fraction(0) == 0)
    }

    @Test func labelIsOneBasedAndClamped() {
        let progress = CookModeProgress(stepCount: 3)
        #expect(progress.label(0) == String(localized: "recipe.cookMode.stepLabel \(1) \(3)"))
        #expect(progress.label(2) == String(localized: "recipe.cookMode.stepLabel \(3) \(3)"))
        #expect(progress.label(99) == String(localized: "recipe.cookMode.stepLabel \(3) \(3)"))
    }

    @Test func fractionIncludesCurrentPage() {
        let progress = CookModeProgress(stepCount: 4)
        #expect(progress.fraction(0) == 0.25)
        #expect(progress.fraction(1) == 0.5)
        #expect(progress.fraction(3) == 1)
    }
}
