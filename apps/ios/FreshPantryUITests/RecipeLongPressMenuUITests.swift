import XCTest

/// Guards the fix for「食谱页面项目长按没有反馈」: a recipe card long-press now
/// surfaces a quick-action 上下文菜单 (收藏 / 加入膳食计划 / 加购缺料 / 自建食谱 编辑·删除),
/// matching 库存 / 购物 / 膳食计划. Before the fix the cards had NO `.contextMenu`,
/// so a long-press did nothing.
///
/// Filters the hermetic UI-test catalog to one deterministic recipe (so the card
/// is isolated), long-presses it, and asserts the menu surfaced. The signal is the
/// 「加入膳食计划」action — it exists ONLY inside the contextMenu (the card's own
/// heart already carries a「收藏」label, so that one can't prove the menu opened).
final class RecipeLongPressMenuUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLongPressShowsQuickActionMenu() {
        let app = XCUIApplication()
        // `-uiTesting`: hermetic stores; `-initialTab recipes` lands on the 食谱 list.
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans", "-uiTesting", "-initialTab", "recipes"]
        app.launch()

        // Isolate a single, always-present test recipe via the search field so
        // exactly one card is on screen to long-press.
        let search = app.textFields["搜索菜谱或食材"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "食谱搜索框未出现")
        search.tap()
        search.typeText("咖喱炒蟹")

        let card = app.staticTexts["咖喱炒蟹"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "搜索结果「咖喱炒蟹」未出现")

        // Long-press → the quick-action menu (the behavior under test).
        card.press(forDuration: 1.1)

        // 「加入膳食计划」lives ONLY in the contextMenu ⇒ its appearance proves the
        // long-press finally gives feedback.
        let plan = app.buttons["加入膳食计划"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5), "长按食谱卡片未弹出快捷菜单")

        // Capture the menu for a visual look.
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "recipe-longpress-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
