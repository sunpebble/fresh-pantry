import SwiftUI
import UIKit

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
    func label(_ index: Int) -> String { "第 \(clamped(index) + 1) / \(stepCount) 步" }

    /// Completed fraction including the current page (drives the progress bar).
    func fraction(_ index: Int) -> Double {
        guard stepCount > 0 else { return 0 }
        return Double(clamped(index) + 1) / Double(stepCount)
    }
}

/// Full-screen cooking mode (fullScreenCover): one swipeable page per step with
/// large readable text, 上一步/下一步 controls (完成 on the last page), a 食材速查
/// sheet, and an idle-timer override so the screen stays awake at the stove.
/// Timers / Live Activities / voice are explicitly out of scope this round.
struct CookModeView: View {
    let title: String
    let steps: [String]
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
                        Text("食材")
                            .font(.fkLabelMedium)
                    }
                    .foregroundStyle(Color.fkPrimaryContainer)
                    .padding(.horizontal, FkSpacing.md)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.fkPrimarySoft))
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel("查看食材清单")
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
            .accessibilityLabel("退出烹饪模式")
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
    /// truncation.
    private func stepPage(index: Int, text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                Text(progress.label(index))
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkPrimary)
                Text(text)
                    .font(Self.stepFont)
                    .foregroundStyle(Color.fkOnSurface)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(FkSpacing.lg)
            .padding(.top, FkSpacing.md)
        }
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
                    Text("上一步")
                        .font(.fkLabelLarge)
                }
                .foregroundStyle(progress.isFirst(stepIndex) ? Color.fkOnSurfaceVariant : Color.fkOnSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.fkSurfaceContainer))
            }
            .buttonStyle(.fkPressable)
            .disabled(progress.isFirst(stepIndex))
            .accessibilityLabel("上一步")

            if progress.isLast(stepIndex) {
                Button {
                    onFinish()
                    dismiss()
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("完成")
                            .font(.fkLabelLarge)
                    }
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.fkPrimary))
                }
                .buttonStyle(.fkPressable)
                .accessibilityLabel("完成并退出烹饪模式")
            } else {
                Button {
                    withAnimation(FkMotion.animation(FkMotion.emphasized, reduceMotion: reduceMotion)) {
                        stepIndex = progress.next(after: stepIndex)
                    }
                } label: {
                    HStack(spacing: FkSpacing.xs) {
                        Text("下一步")
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
                .accessibilityLabel("下一步")
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
                                if !ingredient.amount.trimmed.isEmpty {
                                    Text(ingredient.amount)
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
            .navigationTitle("食材速查")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showIngredients = false }
                }
            }
            .tint(.fkPrimary)
        }
        .presentationDetents([.medium, .large])
    }
}
