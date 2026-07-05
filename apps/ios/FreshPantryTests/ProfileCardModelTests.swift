import XCTest
@testable import FreshPantry

final class ProfileCardModelTests: XCTestCase {
    func test_title_usesDisplayName_whenPresent() {
        let model = ProfileCardModel(displayName: "小白", nickname: "", accountFallback: "a@b.com")
        XCTAssertEqual(model.title, "小白")
    }

    func test_title_fallsBackToPrompt_whenDisplayNameBlank() {
        let model = ProfileCardModel(displayName: "   ", nickname: "x", accountFallback: "a@b.com")
        XCTAssertEqual(model.title, String(localized: "settings.profile.setupPrompt"))
    }

    func test_subtitle_prefersNickname_whenPresent() {
        let model = ProfileCardModel(displayName: "小白", nickname: "阿白", accountFallback: "a@b.com")
        XCTAssertEqual(model.subtitle, "阿白")
    }

    func test_subtitle_fallsBackToAccount_whenNicknameBlank() {
        let model = ProfileCardModel(displayName: "小白", nickname: "  ", accountFallback: "a@b.com")
        XCTAssertEqual(model.subtitle, "a@b.com")
    }
}
