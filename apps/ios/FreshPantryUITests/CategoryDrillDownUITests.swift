import XCTest

/// Regression guard for the cross-tab intent race.
///
/// Tapping a 首页 食材分类 tile must (1) switch to the 库存 tab AND (2) filter the
/// list to that category — EVERY time, including repeat taps. The bug this guards
/// against: the warm-path delivery used `.onChange(of: pendingCategory)`, which
/// never fires for a value set in the SAME transaction that switches to the
/// (re)created tab view, so the filter applied only intermittently. The fix
/// switched the warm path to `.task(id:)`. See `fresh-pantry-cross-tab-intent`.
///
/// We assert BEHAVIOR (the filtered list content), not the chip's selected trait,
/// so the test is independent of SwiftUI→XCUIElement accessibility-trait mapping.
/// We drive the real `TabView` lifecycle (the only place this race surfaces) and
/// tap several categories in a row — the first tap exercises the cold path, the
/// rest the warm path that used to drop the intent.
final class CategoryDrillDownUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testHomeCategoryDrillDownAppliesInventoryFilter() {
        let app = XCUIApplication()
        // `-uiTesting`: clean in-memory store + wiped defaults + signed-out launch,
        // so the DEBUG seeder fills deterministic sample inventory.
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans", "-uiTesting", "-initialTab", "home"]
        app.launch()

        // (category, a member item, a non-member item) — all from the DEBUG seed
        // (InventorySeeder.specs). First row = cold path (first 库存 visit); the
        // rest = the warm path that used to lose the intent intermittently.
        let cases: [(category: String, member: String, absent: String)] = [
            ("果蔬生鲜", "苹果", "牛奶"),
            ("肉类海鲜", "鸡胸肉", "苹果"),
            ("乳品蛋类", "牛奶", "苹果"),
        ]

        for (index, step) in cases.enumerated() {
            let attempt = index + 1
            goHome(app)
            let tile = app.buttons["home.category.\(step.category)"]
            XCTAssertTrue(
                tile.waitForExistence(timeout: 10),
                "找不到首页分类格子「\(step.category)」(种子数据未就绪?)"
            )
            tile.tap()

            // Filter applied ⇒ a member row appears (proves the tab switched AND
            // re-filtered to THIS category — the warm-path failure left the prior
            // category showing) ...
            let member = app.staticTexts[step.member]
            XCTAssertTrue(
                member.waitForExistence(timeout: 5),
                "点「\(step.category)」后库存未显示该类食材「\(step.member)」(跨 tab 意图丢失,第 \(attempt) 次)"
            )
            // ... and a non-member row disappears (proves it's actually filtered,
            // not just showing the full list).
            let absent = app.staticTexts[step.absent]
            XCTAssertTrue(
                absent.waitForNonExistence(timeout: 5),
                "点「\(step.category)」后筛选未生效:非本类的「\(step.absent)」仍在列表(第 \(attempt) 次)"
            )
        }
    }

    /// Returns to the 首页 tab. `sidebarAdaptable` is a bottom tab bar on iPhone
    /// (queryable via `tabBars`) but a top tab/sidebar control on iPad, where
    /// "首页" resolves to multiple buttons — so the fallback takes `firstMatch`
    /// rather than the ambiguous whole query (which throws "Multiple matching").
    @MainActor
    private func goHome(_ app: XCUIApplication) {
        let tabButton = app.tabBars.buttons["首页"]
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
        } else {
            app.buttons["首页"].firstMatch.tap()
        }
    }
}
