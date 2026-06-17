import SwiftUI

/// Press-feedback button style ported from Flutter `FkAnimatedPressable`:
/// a subtle scale-down on press plus a light sensory tap. Collapses to no
/// animation under Reduce Motion (accessibility + keeps UI tests from hanging
/// on never-settling animations).
struct FkPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? FkMotion.pressScale : 1.0)
            .animation(FkMotion.animation(FkMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FkPressableButtonStyle {
    /// `.buttonStyle(.fkPressable)` — the standard tappable-surface feedback.
    static var fkPressable: FkPressableButtonStyle { FkPressableButtonStyle() }
}

/// Staggered fade+rise entrance ported from Flutter `FkEntrance`. No-op under
/// Reduce Motion (renders fully visible immediately).
///
/// In a `LazyVStack`/`List`, cells are created lazily and fire `onAppear` as they
/// scroll into view, so a naive entrance RE-PLAYS for every row revealed by
/// scrolling — the "I can feel new items loading as I scroll" symptom. The entrance
/// is therefore gated behind a list-scoped window (`\.fkEntranceActive`, opened by
/// `fkEntranceWindow()`): the first screen's stagger plays once, then the window
/// closes and any cell appearing afterwards (scrolled in, or scrolled back to)
/// renders immediately. A list that does NOT wrap itself in `fkEntranceWindow()`
/// keeps the legacy always-animate behavior (the environment default is `true`).
struct FkEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fkEntranceActive) private var entranceActive
    @State private var appeared = false

    func body(content: Content) -> some View {
        let resolved = Self.isResolved(appeared: appeared, reduceMotion: reduceMotion, entranceActive: entranceActive)
        let delay = Double(min(index, FkMotion.staggerMaxItems)) * FkMotion.staggerStep
        return content
            .opacity(resolved ? 1 : 0)
            .offset(y: resolved ? 0 : FkMotion.entranceOffset)
            .onAppear {
                guard Self.animatesOnAppear(reduceMotion: reduceMotion, entranceActive: entranceActive) else { return }
                withAnimation(FkMotion.entrance.delay(delay)) { appeared = true }
            }
    }

    /// Whether the item should render at its final (visible, un-offset) state: once
    /// it has appeared, under Reduce Motion, OR once its list's entrance window has
    /// closed (so a cell revealed by scrolling does not start hidden+offset and
    /// re-animate — the scroll pop-in this whole gating exists to kill).
    static func isResolved(appeared: Bool, reduceMotion: Bool, entranceActive: Bool) -> Bool {
        appeared || reduceMotion || !entranceActive
    }

    /// Whether `onAppear` should schedule the staggered entrance — only with motion
    /// allowed AND while the list's entrance window is still open.
    static func animatesOnAppear(reduceMotion: Bool, entranceActive: Bool) -> Bool {
        !reduceMotion && entranceActive
    }
}

/// Whether `fkEntrance` children are still inside their list's initial entrance
/// window. Default `true` so a view with no `fkEntranceWindow()` keeps the legacy
/// always-animate behavior; a scrolling list wraps its container in
/// `fkEntranceWindow()` to flip this to `false` once the first screen has entered.
private struct FkEntranceActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var fkEntranceActive: Bool {
        get { self[FkEntranceActiveKey.self] }
        set { self[FkEntranceActiveKey.self] = newValue }
    }
}

/// Opens a staggered-entrance window for the `fkEntrance` children below, then
/// closes it once the first screen has finished entering (`FkMotion.entranceWindow`
/// later). After it closes, rows that a `LazyVStack`/`List` creates lazily while
/// scrolling — or recreates when scrolled back to — render immediately instead of
/// re-playing the fade+rise. Attach to the scrolling container that holds the
/// `fkEntrance` rows (a no-op under Reduce Motion, where the entrance is already off).
struct FkEntranceWindow: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = true

    func body(content: Content) -> some View {
        content
            .environment(\.fkEntranceActive, active)
            .task {
                // Let the first screen's stagger finish, then close the window so
                // scrolled-in cells stop animating. Reduce Motion never animates, so
                // there's nothing to wait out.
                guard active, !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(FkMotion.entranceWindow))
                guard !Task.isCancelled else { return }
                active = false
            }
    }
}

extension View {
    /// Applies the staggered entrance for the item at `index`.
    func fkEntrance(index: Int = 0) -> some View {
        modifier(FkEntrance(index: index))
    }

    /// Scopes a staggered-entrance window to this container — see `FkEntranceWindow`.
    func fkEntranceWindow() -> some View {
        modifier(FkEntranceWindow())
    }
}
