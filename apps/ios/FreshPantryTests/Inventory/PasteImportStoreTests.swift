import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the AI paste-import seam: a pasted text + an injected
/// `chatFn` produces review-ready `IntakeProposal`s against live inventory, and
/// the error branches surface the right Chinese message. The chat seam is faked
/// so no network / API key is needed.
/// Thread-safe call counter so a `@Sendable` fake `chatFn` can record invocations.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
struct PasteImportStoreTests {
    private func makeRepo() throws -> InventoryRepository {
        let container = try ModelContainerFactory.makeInMemory()
        return InventoryRepository(modelContainer: container)
    }

    private let settings = AiSettings(
        baseUrl: "https://example.com/v1",
        apiKey: "key",
        model: "gpt-4o",
        timeout: 30
    )

    private func makeStore(
        _ repo: InventoryRepository,
        chatFn: @escaping AiChatFn,
        household: String = "home"
    ) -> PasteImportStore {
        PasteImportStore(
            aiSettings: settings,
            inventoryRepository: repo,
            householdID: household,
            chatFn: chatFn
        )
    }

    // MARK: Successful parse → proposals

    @Test func parsesTextIntoProposals() async throws {
        let repo = try makeRepo()
        let raw = #"[{"name":"牛奶","quantity":"2","unit":"盒","category":"乳品蛋类","storage":"fridge","shelfLifeDays":7}]"#
        let store = makeStore(repo) { _ in raw }
        store.text = "牛奶两盒"

        await store.parse()

        #expect(store.errorMessage == nil)
        #expect(store.isParsing == false)
        let proposals = try #require(store.proposals)
        #expect(proposals.count == 1)
        #expect(proposals[0].name == "牛奶")
        #expect(proposals[0].action == .newRow) // empty inventory -> new row
        #expect(proposals[0].origin == .ai)
    }

    // MARK: Blank text is a no-op (canParse false)

    @Test func blankTextDoesNotParse() async throws {
        let repo = try makeRepo()
        let callCount = CallCounter()
        let store = makeStore(repo) { _ in callCount.increment(); return "[]" }
        store.text = "   "
        #expect(store.canParse == false)

        await store.parse()
        #expect(callCount.value == 0)
        #expect(store.proposals == nil)
        #expect(store.errorMessage == nil)
    }

    // MARK: AI error surfaces its Chinese message

    @Test func aiErrorSurfacesMessage() async throws {
        let repo = try makeRepo()
        let store = makeStore(repo) { _ in throw AiError.auth("认证失败 (401)") }
        store.text = "牛奶"

        await store.parse()
        #expect(store.errorMessage == "认证失败 (401)")
        #expect(store.proposals == nil)
    }

    // MARK: Empty result yields a friendly note (not a crash / empty review)

    @Test func emptyResultYieldsFriendlyNotice() async throws {
        let repo = try makeRepo()
        let store = makeStore(repo) { _ in "[]" }
        store.text = "没有食材的文本"

        await store.parse()
        #expect(store.proposals == nil)
        #expect(store.errorMessage == String(localized: "inventory.pasteImport.textEmptyResult"))
    }

    // MARK: consumeProposals clears the one-shot route

    @Test func consumeProposalsClearsResult() async throws {
        let repo = try makeRepo()
        let store = makeStore(repo) { _ in #"[{"name":"鸡蛋"}]"# }
        store.text = "鸡蛋"

        await store.parse()
        #expect(store.proposals != nil)
        store.consumeProposals()
        #expect(store.proposals == nil)
    }
}
