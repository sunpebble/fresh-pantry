import SwiftUI

/// Motion tokens ported from Flutter `AppDuration` / `AppMotionCurves` /
/// `AppMotion`. Tone: restrained and premium — quick, with a settled finish.
///
/// Every animated primitive MUST route through `FkMotion.animation(_:reduceMotion:)`
/// (or read `\.accessibilityReduceMotion`) so motion collapses when the user
/// asks for reduced motion — both an accessibility requirement and what keeps
/// UI tests from hanging on never-settling animations.
enum FkMotion {
    // Durations (seconds)
    static let fast: TimeInterval = 0.12 // 按压 / 微反馈
    static let normal: TimeInterval = 0.18 // 折叠 / 状态切换
    static let slow: TimeInterval = 0.25 // 入场 / cross-fade
    static let page: TimeInterval = 0.24 // 页面转场
    static let shimmer: TimeInterval = 1.4 // 微光循环

    // Parameters
    static let pressScale: CGFloat = 0.97 // 按压缩放终值
    static let entranceOffset: CGFloat = 8 // 入场上移
    static let staggerStep: TimeInterval = 0.05 // 列表交错步长
    static let staggerMaxItems = 8 // 交错封顶
    /// 一个列表入场窗口保持开启的时长。覆盖最坏情况下交错项(封顶延迟)再加一段
    /// 入场时长,确保首屏交错动画完整播完;此后由 `fkEntranceWindow()` 关闭窗口,
    /// `LazyVStack`/`List` 滚动时才懒创建的 cell 直接以终态呈现,不再重播入场——
    /// 否则每个滚入视口的新行都淡入+上移,读起来像「列表一直在加载」。
    static let entranceWindow: TimeInterval = Double(staggerMaxItems) * staggerStep + slow

    // Curves → SwiftUI animations
    static let standard = Animation.easeOut(duration: normal) // 平稳减速
    static let press = Animation.easeOut(duration: fast)
    static let entrance = Animation.easeOut(duration: slow)
    /// 强调减速(页面转场):对应 cubic(0.2, 0, 0, 1)。
    static let emphasized = Animation.timingCurve(0.2, 0, 0, 1, duration: page)

    /// Returns `nil` (no animation) when reduce-motion is on, else the token.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
