import Foundation
import Testing
@testable import FreshPantry

struct AiChatAccessTests {
    @Test func byokWinsRegardlessOfPro() {
        let byok = AiSettings(baseUrl: "https://my.llm/v1", apiKey: "k", model: "m")
        #expect(AiChatAccess.resolve(byok: byok, isPro: false) == .byok(byok))
        #expect(AiChatAccess.resolve(byok: byok, isPro: true) == .byok(byok))
    }

    @Test func proWithoutByokUsesBuiltIn() {
        #expect(AiChatAccess.resolve(byok: .empty, isPro: true) == .builtIn)
    }

    @Test func freeWithoutByokNeedsPro() {
        #expect(AiChatAccess.resolve(byok: .empty, isPro: false) == .needsPro)
    }

    @Test func builtInSettingsPointAtWorker() {
        let settings = AiChatAccess.builtInSettings(
            apiBaseURL: URL(string: "https://api.freshpantry.sunpebblelabs.com")!,
            accessToken: "tok"
        )
        // normalizeAiBaseUrl 会补 /v1 → 最终打到 /ai/v1/chat/completions
        #expect(settings.baseUrl == "https://api.freshpantry.sunpebblelabs.com/ai")
        #expect(settings.apiKey == "tok")
        #expect(settings.model == "deepseek-v4-flash")
        #expect(settings.isConfigured)
    }
}
