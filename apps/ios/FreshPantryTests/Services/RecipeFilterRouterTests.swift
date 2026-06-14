import Foundation
import Testing
@testable import FreshPantry

/// #18 临期→做这道菜 cross-tab router — capture / consume / trim semantics.
@MainActor
struct RecipeFilterRouterTests {
    @Test func captureThenConsumeReturnsAndClears() {
        let router = RecipeFilterRouter()
        router.capture(ingredient: "番茄")
        #expect(router.pendingIngredient == "番茄")
        #expect(router.consume() == "番茄")
        #expect(router.pendingIngredient == nil)
    }

    @Test func captureTrimsAndIgnoresBlank() {
        let router = RecipeFilterRouter()
        router.capture(ingredient: "  鸡蛋 ")
        #expect(router.pendingIngredient == "鸡蛋")
        router.capture(ingredient: "   ")
        #expect(router.pendingIngredient == nil)
    }

    @Test func clearResets() {
        let router = RecipeFilterRouter()
        router.capture(ingredient: "牛奶")
        router.clear()
        #expect(router.pendingIngredient == nil)
    }
}
