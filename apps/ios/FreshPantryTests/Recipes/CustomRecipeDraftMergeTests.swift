import Foundation
import Testing
@testable import FreshPantry

/// Tests for `CustomRecipeDraft.mergingParsed(_:over:)` — the AI URL-import
/// overwrite merge: the parsed draft wins wholesale, but a parse with NO cover
/// keeps the form's already-picked one (Dart `_applyRecipeDraft` parity), and
/// the merge reports the cover it displaced so the form can delete a local
/// `file://` orphan.
struct CustomRecipeDraftMergeTests {
    private func parsedDraft(imageUrl: String? = nil) -> CustomRecipeDraft {
        CustomRecipeDraft(
            name: "解析菜",
            category: "川菜",
            cookingMinutes: "25",
            difficulty: 4,
            description: "解析出的简介",
            ingredients: [.init(name: "豆腐", quantity: "1", unit: "块")],
            steps: [.init(text: "切块"), .init(text: "下锅")],
            imageUrl: imageUrl
        )
    }

    private func filledForm(imageUrl: String? = nil) -> CustomRecipeDraft {
        CustomRecipeDraft(
            name: "手填菜",
            category: "家常",
            cookingMinutes: "10",
            difficulty: 2,
            ingredients: [.init(name: "鸡蛋", quantity: "2", unit: "个")],
            steps: [.init(text: "打蛋")],
            imageUrl: imageUrl
        )
    }

    @Test func parsedFieldsWinWholesale() {
        let merge = CustomRecipeDraft.mergingParsed(parsedDraft(), over: filledForm())
        #expect(merge.merged.name == "解析菜")
        #expect(merge.merged.category == "川菜")
        #expect(merge.merged.cookingMinutes == "25")
        #expect(merge.merged.ingredients.map(\.name) == ["豆腐"])
        #expect(merge.merged.steps.map(\.text) == ["切块", "下锅"])
    }

    @Test func parsedWithoutCoverKeepsPickedCover() {
        let local = "file:///covers/picked.jpg"
        let merge = CustomRecipeDraft.mergingParsed(parsedDraft(), over: filledForm(imageUrl: local))
        // The parse found no cover — the picked one survives, nothing displaced.
        #expect(merge.merged.imageUrl == local)
        #expect(merge.replacedCover == nil)
    }

    @Test func parsedCoverDisplacesCurrentAndReportsIt() {
        let local = "file:///covers/picked.jpg"
        let remote = "https://example.com/cover.jpg"
        let merge = CustomRecipeDraft.mergingParsed(parsedDraft(imageUrl: remote), over: filledForm(imageUrl: local))
        #expect(merge.merged.imageUrl == remote)
        // The displaced cover is reported so the caller can delete a local orphan.
        #expect(merge.replacedCover == local)
    }

    @Test func noCurrentCoverReportsNothing() {
        let merge = CustomRecipeDraft.mergingParsed(
            parsedDraft(imageUrl: "https://example.com/cover.jpg"),
            over: filledForm()
        )
        #expect(merge.merged.imageUrl == "https://example.com/cover.jpg")
        #expect(merge.replacedCover == nil)
    }

    @Test func identicalCoverReportsNothing() {
        let same = "https://example.com/cover.jpg"
        let merge = CustomRecipeDraft.mergingParsed(parsedDraft(imageUrl: same), over: filledForm(imageUrl: same))
        #expect(merge.merged.imageUrl == same)
        #expect(merge.replacedCover == nil)
    }
}
