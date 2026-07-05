import SwiftUI
import UIKit
import Combine

/// Pure paging math for Cook Mode: clamps the step index, answers the
/// 上一步/下一步 boundary questions, and formats the per-page "第 x / n 步"
/// label. Kept view-free so the boundary behavior is unit-testable
/// (`CookModeProgressTests`).
struct CookModeProgress: Equatable, Sendable {
    let stepCount: Int

    /// `index` forced into the valid page range; 0 when there are no steps.
    func clamped(_ index: Int) -> Int {
        guard stepCount > 0 else { return 0 }
        return min(max(index, 0), stepCount - 1)
    }

    /// One page forward, stopping at the last page.
    func next(after index: Int) -> Int { clamped(index + 1) }

    /// One page back, stopping at the first page.
    func previous(before index: Int) -> Int { clamped(index - 1) }

    func isFirst(_ index: Int) -> Bool { clamped(index) == 0 }

    /// True on the last page — and for a step-less recipe, so the 完成
    /// affordance is never stranded.
    func isLast(_ index: Int) -> Bool { clamped(index) >= stepCount - 1 }

    /// "第 x / n 步" (1-based, clamped).
    func label(_ index: Int) -> String {
        String(localized: "recipe.cookMode.stepLabel \(clamped(index) + 1) \(stepCount)")
    }

    /// Completed fraction including the current page (drives the progress bar).
    func fraction(_ index: Int) -> Double {
        guard stepCount > 0 else { return 0 }
        return Double(clamped(index) + 1) / Double(stepCount)
    }
}

/// Full-screen cooking mode (fullScreenCover): one swipeable page per step with
/// large readable text, 上一步/下一步 controls (完成 on the last page), a 食材速查
/// sheet, an idle-timer override so the screen stays awake at the stove, and a
/// per-step countdown timer when the step carries a pipeline-parsed duration.
struct CookModeView: View {
    let title: String
    let steps: [String]
    /// 每步时长(秒,与 `steps` 索引对齐;某步无时长为 nil)。空数组 = 整菜无时长
    /// 数据。驱动每步右上角的「计时」倒计时按钮。
    var stepDurations: [Int?] = []
    /// Already scaled by the caller's 备料倍数 (`RecipeDetailView.scaledIngredients`)
    /// — Cook Mode renders amounts verbatim so scaling keeps a single source.
    let ingredients: [RecipeIngredient]
    /// Called when the user taps 完成 on the last page (NOT the X close — that's
    /// an abandon, this is "the dish got cooked"). Fired before `dismiss()` so
    /// the presenter can flag follow-ups for its own onDismiss.
    var onFinish: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepIndex = 0
    @State private var showIngredients = false

    private var progress: CookModeProgress { CookModeProgress(stepCount: steps.count) }

    /// Glance-from-the-stove step text — larger than any body token; the CJK
    /// glyphs fall back to the system font, Latin renders in Manrope.
    private static let stepFont = Font.fk(.text, size: 22, weight: .medium, relativeTo: .title2)

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, FkSpacing.lg)
                .padding(.top, FkSpacing.md)
            progressBar
                .padding(.horizontal, FkSpacing.lg)
                .padding(.top, FkSpacing.md)
            pager
            controls
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, FkSpacing.md)
        }
        .background(Color.fkSurface.ignoresSafeArea())
        .sheet(isPresented: $showIngredients) { ingredientsSheet }
        // 防熄屏: keep the screen awake while cooking. The override MUST be
        // restored on EVERY exit path — close button, 完成, or any system
        // dismissal of the fullScreenCover — so the restore lives solely in
        // onDisappear (which fires for all of them) rather than being repeated
        // at each dismiss call site. Both closures inherit @MainActor from the
        // view body, which `UIApplication.shared` requires.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Top bar (食谱名 + 食材速查 + 关闭)

    private var topBar: some View {
        HStack(spacing: FkSpacing.md) {
            Text(title)
                .font(.fkTitleLarge)
                .foregroundStyle(Color.fkOnSurface)
                .lineLimit(1)
            Spacer(minLength: FkSpacing.sm)
            if !ingredients.isEmpty {
                Button {
                    showIngredients = true
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(localized: "recipe.cookMode.ingredients"))
                            .font(.fkLabelMedium)
                    }
                    .foregroundStyle(Color.fkPrimaryContainer)
                    .padding(.horizontal, FkSpacing.md)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.fkPrimarySoft))
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel(String(localized: "recipe.cookMode.viewIngredients"))
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.fkSurfaceContainer))
            }
            .buttonStyle(.fkPressable)
            .accessibilityLabel(String(localized: "recipe.cookMode.exit"))
        }
    }

    // MARK: Page indicator

    /// Thin progress capsule — mirrors the detail screen's steps progress bar
    /// and scales to long recipes better than page dots would.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.fkSurfaceContainer)
                Capsule().fill(Color.fkPrimary)
                    .frame(width: geo.size.width * progress.fraction(stepIndex))
            }
        }
        .frame(height: 5)
        .animation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion), value: stepIndex)
        .accessibilityHidden(true)
    }

    // MARK: Step pager

    private var pager: some View {
        TabView(selection: $stepIndex) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                stepPage(index: index, text: step)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// One full step per page; the ScrollView keeps long steps readable without
    /// truncation. When the step has a parsed duration, a 计时 countdown button
    /// sits beside the page label.
    private func stepPage(index: Int, text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                HStack(spacing: FkSpacing.md) {
                    Text(progress.label(index))
                        .font(.fkLabelLarge)
                        .foregroundStyle(Color.fkPrimary)
                    Spacer(minLength: FkSpacing.sm)
                    if let seconds = durationForStep(index) {
                        // `.id(index)` 让换步时倒计时归零重置(SwiftUI 重建该视图)。
                        StepCountdownButton(totalSeconds: seconds).id(index)
                    }
                }
                // #10 inline ingredient amounts + lanfan's per-step countdown coexist.
                StepAnnotatedText(step: text, ingredients: ingredients)
                    .font(Self.stepFont)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(FkSpacing.lg)
            .padding(.top, FkSpacing.md)
        }
    }

    /// The step's effective countdown seconds, or nil when it has no parsed
    /// duration (array shorter than steps, a nil element, or a non-positive value).
    private func durationForStep(_ index: Int) -> Int? {
        guard stepDurations.indices.contains(index), let seconds = stepDurations[index], seconds > 0 else {
            return nil
        }
        return seconds
    }

    // MARK: 上一步 / 下一步 / 完成

    private var controls: some View {
        HStack(spacing: FkSpacing.md) {
            Button {
                withAnimation(FkMotion.animation(FkMotion.emphasized, reduceMotion: reduceMotion)) {
                    stepIndex = progress.previous(before: stepIndex)
                }
            } label: {
                HStack(spacing: FkSpacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(localized: "recipe.cookMode.previous"))
                        .font(.fkLabelLarge)
                }
                .foregroundStyle(progress.isFirst(stepIndex) ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.fkSurfaceContainer))
            }
            .buttonStyle(.fkPressable)
            .disabled(progress.isFirst(stepIndex))
            .accessibilityLabel(String(localized: "recipe.cookMode.previous"))

            if progress.isLast(stepIndex) {
                Button {
                    onFinish()
                    dismiss()
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text(String(localized: "recipe.cookMode.finish"))
                            .font(.fkLabelLarge)
                    }
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.fkPrimary))
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel(String(localized: "recipe.cookMode.finishAndExit"))
            } else {
                Button {
                    withAnimation(FkMotion.animation(FkMotion.emphasized, reduceMotion: reduceMotion)) {
                        stepIndex = progress.next(after: stepIndex)
                    }
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        Text(String(localized: "recipe.cookMode.next"))
                            .font(.fkLabelLarge)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.fkPrimary))
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel(String(localized: "recipe.cookMode.next"))
            }
        }
    }

    // MARK: 食材速查

    /// Name + (scaled) amount rows so mid-cook checks don't require leaving
    /// Cook Mode.
    private var ingredientsSheet: some View {
        NavigationStack {
            ScrollView {
                FkCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                            HStack(spacing: FkSpacing.sm) {
                                Text(ingredient.name)
                                    .font(.fkBodyMedium)
                                    .foregroundStyle(Color.fkOnSurface)
                                Spacer(minLength: FkSpacing.md)
                                if !ingredient.fractionAmount.trimmed.isEmpty {
                                    Text(ingredient.fractionAmount)
                                        .font(.fkLabelMedium)
                                        .foregroundStyle(Color.fkOnSurfaceVariant)
                                }
                            }
                            .padding(FkSpacing.lg)
                            if index < ingredients.count - 1 {
                                Rectangle().fill(Color.fkHair).frame(height: 0.5)
                            }
                        }
                    }
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .navigationTitle(String(localized: "recipe.cookMode.ingredientsQuickCheck"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "recipe.cookMode.close")) { showIngredients = false }
                }
            }
            .tint(.fkPrimary)
        }
        .presentationDetents([.medium, .large])
    }
}

/// 单步倒计时按钮:点击开始 → mm:ss 递减 → 再点暂停 / 继续。换步时父级用 `.id`
/// 重建即重置。归零震动一次并停。纯展示状态机(格式化见已测的 `CookStepTimer`)。
private struct StepCountdownButton: View {
    let totalSeconds: Int
    @State private var remaining: Int?
    @State private var running = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: FkSpacing.xs) {
                Image(systemName: running ? "pause.fill" : (remaining == nil ? "timer" : "play.fill"))
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.fkLabelLarge)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.fkPrimaryContainer)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
        .onReceive(ticker) { _ in tick() }
        .accessibilityLabel(
            running
                ? String(localized: "recipe.cookMode.timerPaused \(CookStepTimer.countdown(remaining: remaining ?? 0))")
                : String(localized: "recipe.cookMode.timerStart \(CookStepTimer.label(seconds: totalSeconds))")
        )
    }

    private var label: String {
        if let remaining { return CookStepTimer.countdown(remaining: remaining) }
        return String(localized: "recipe.cookMode.timerLabel \(CookStepTimer.label(seconds: totalSeconds))")
    }

    private func toggle() {
        if running {
            running = false
        } else {
            if remaining == nil || remaining == 0 { remaining = totalSeconds }
            running = true
        }
    }

    private func tick() {
        guard running, let current = remaining else { return }
        if current > 1 {
            remaining = current - 1
        } else {
            remaining = 0
            running = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
