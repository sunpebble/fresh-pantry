import XCTest

/// Captures App Store screenshots using FreshPantry's hermetic `-uiTesting`
/// seed and `-initialTab` snapshot hook. English version for the en-US locale.
final class ScreenshotTests: XCTestCase {

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent(name))
        let a = XCTAttachment(screenshot: shot); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func baseArgs(_ tab: String) -> [String] {
        ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US", "-uiTesting", "-initialTab", tab]
    }

    @MainActor
    func testCaptureScreenshots() {
        let shots: [(tab: String, wait: UInt32, name: String, scroll: Bool)] = [
            ("home",      10, "fp-en-1-home.png",      true),
            ("inventory", 8,  "fp-en-2-inventory.png", false),
            ("recipes",   8,  "fp-en-3-recipes.png",   false),
        ]
        for s in shots {
            let app = XCUIApplication()
            app.launchArguments += baseArgs(s.tab)
            app.launch()
            sleep(s.wait)
            if s.scroll { app.swipeUp() ; sleep(2) }
            save(XCUIScreen.main.screenshot(), s.name)
            app.terminate()
        }
    }
}
