import Foundation
import Testing
@testable import FreshPantry

@MainActor
struct WidgetDeepLinkRouterTests {
    @Test func parsesKnownHosts() {
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://expiring")!) == .expiring)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://mealplan")!) == .mealPlan)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://shopping")!) == .shopping)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://waste")!) == .waste)
    }

    @Test func ignoresUnknownAndOtherSchemes() {
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://import-recipe?url=x")!) == nil)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://some-invite-token")!) == nil)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "https://example.com/expiring")!) == nil)
    }

    @Test func captureSetsPendingForOwnedURLOnly() {
        let router = WidgetDeepLinkRouter()
        #expect(router.capture(url: URL(string: "freshpantry://shopping")!) == true)
        #expect(router.pending == .shopping)
        #expect(router.capture(url: URL(string: "freshpantry://import-recipe")!) == false)
        #expect(router.pending == .shopping) // 不被无关 URL 清掉
    }

    @Test func consumeClearsPending() {
        let router = WidgetDeepLinkRouter()
        _ = router.capture(url: URL(string: "freshpantry://waste")!)
        #expect(router.consume() == .waste)
        #expect(router.pending == nil)
        #expect(router.consume() == nil)
    }
}
