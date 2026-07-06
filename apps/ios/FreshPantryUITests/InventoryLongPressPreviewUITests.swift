import XCTest

/// Demonstrates (and guards) the new 库存 long-press behavior: a long-press now
/// peeks a preview card + quick-action menu (查看详情 / 编辑 / 加入购物清单 / 删除)
/// instead of entering multi-select. Multi-select moved to the 顶栏 ⋯「多选」.
///
/// Drives the real seeded inventory (`-uiTesting` → DEBUG `InventorySeeder`),
/// long-presses a known row, asserts the menu surfaced, and attaches a screenshot
/// of the peek for visual confirmation.
final class InventoryLongPressPreviewUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLongPressShowsPreviewMenu() {
        let app = XCUIApplication()
        // `-uiTesting`: clean in-memory store + DEBUG seed; `-initialTab inventory`
        // lands directly on the 库存 list.
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans", "-uiTesting", "-initialTab", "inventory"]
        app.launch()

        // A deterministic seeded row (InventorySeeder.specs — same data the
        // CategoryDrillDown test relies on).
        let row = app.staticTexts["苹果"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "库存种子行「苹果」未出现")

        // Long-press → contextMenu peek (the change under test). The old behavior
        // entered multi-select; now it surfaces the quick-action menu.
        row.press(forDuration: 1.1)

        // All four quick actions appear ⇒ it's the preview menu, not selection mode.
        let detail = app.buttons["查看详情"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "长按未弹出预览菜单「查看详情」")
        XCTAssertTrue(app.buttons["编辑"].exists, "预览菜单缺「编辑」")
        XCTAssertTrue(app.buttons["加入购物清单"].exists, "预览菜单缺「加入购物清单」")
        XCTAssertTrue(app.buttons["删除"].exists, "预览菜单缺「删除」")

        // Capture the preview card + menu for a look.
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "inventory-longpress-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
