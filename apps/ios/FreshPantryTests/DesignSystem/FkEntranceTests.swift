import Foundation
import Testing
@testable import FreshPantry

/// Guards the `FkEntrance` staggered-entrance policy. The bug this pins down: in a
/// `LazyVStack`/`List`, cells are created lazily and fire `onAppear` as they scroll
/// into view, so the per-cell entrance (fade + rise) used to RE-PLAY for every row
/// revealed by scrolling — the "I can feel new items loading as I scroll" symptom.
///
/// The fix gates the entrance behind a list-scoped `entranceActive` window: the
/// initial staggered entrance plays once, then the window closes and any cell
/// appearing afterwards (scrolled in, or scrolled back to) renders immediately.
@MainActor
struct FkEntranceTests {
    // MARK: isResolved — should the cell render at its final (visible, un-offset) state?

    @Test func resolvedAfterItHasAppeared() {
        #expect(FkEntrance.isResolved(appeared: true, reduceMotion: false, entranceActive: true))
    }

    @Test func resolvedImmediatelyUnderReduceMotion() {
        #expect(FkEntrance.isResolved(appeared: false, reduceMotion: true, entranceActive: true))
    }

    /// THE FIX: once the list's entrance window has closed, a cell that has not yet
    /// appeared (e.g. just scrolled into view) must render fully resolved — it must
    /// NOT start hidden+offset and animate in. This is what stops the scroll pop-in.
    @Test func resolvedOnceEntranceWindowClosed() {
        #expect(FkEntrance.isResolved(appeared: false, reduceMotion: false, entranceActive: false))
    }

    /// While the window is still open and motion is allowed, a not-yet-appeared cell
    /// starts hidden so it can animate in (the intended first-screen polish).
    @Test func hiddenWhileWindowOpenAndNotYetAppeared() {
        #expect(!FkEntrance.isResolved(appeared: false, reduceMotion: false, entranceActive: true))
    }

    // MARK: animatesOnAppear — should onAppear schedule the entrance animation?

    @Test func animatesOnAppearOnlyInsideWindowWithMotion() {
        #expect(FkEntrance.animatesOnAppear(reduceMotion: false, entranceActive: true))
    }

    @Test func doesNotAnimateUnderReduceMotion() {
        #expect(!FkEntrance.animatesOnAppear(reduceMotion: true, entranceActive: true))
    }

    /// THE FIX (mirror): after the window closes, scrolled-in cells never schedule
    /// the entrance animation.
    @Test func doesNotAnimateOnceWindowClosed() {
        #expect(!FkEntrance.animatesOnAppear(reduceMotion: false, entranceActive: false))
    }

    // MARK: entrance window duration

    /// The window must stay open long enough for the worst-case staggered item (the
    /// capped delay) to finish its entrance, so the first screen's stagger is never
    /// cut off — but no longer, so it closes promptly for scrolling.
    @Test func entranceWindowCoversWorstCaseStagger() {
        #expect(FkMotion.entranceWindow == Double(FkMotion.staggerMaxItems) * FkMotion.staggerStep + FkMotion.slow)
        #expect(FkMotion.entranceWindow > 0)
    }
}
