import Foundation

/// Drives the AI ingredient-import flow: pasted food-list text OR a picked photo
/// → `AiIngredientParser` → `[IngredientDraft]` → `[IntakeProposal]` (resolved
/// against live inventory by the same `IntakeProposalFactory` the manual-add flow
/// uses). The resulting proposals are handed to the EXISTING `IntakeReviewView`
/// for review/apply, so the apply + sync-enqueue logic is never duplicated here.
/// The text and image paths share the same `proposals`/`isParsing`/`errorMessage`
/// state so the review presentation is identical for both.
///
/// States (`isParsing` / `errorMessage`) drive the sheet UI; `AiError.message`
/// surfaces the Chinese error text the user expects.
@Observable
@MainActor
final class PasteImportStore {
    var text: String = ""
    private(set) var isParsing = false
    private(set) var errorMessage: String?
    /// Set when parsing succeeds with at least one draft — the view observes this
    /// to push the review screen.
    private(set) var proposals: [IntakeProposal]?

    private let aiSettings: AiSettings
    private let inventoryRepository: InventoryRepository
    private let householdID: String
    /// Injectable chat seam — defaults to the live `AiClient`, overridden in tests.
    private let chatFn: AiChatFn

    init(
        aiSettings: AiSettings,
        inventoryRepository: InventoryRepository,
        householdID: String,
        chatFn: AiChatFn? = nil
    ) {
        self.aiSettings = aiSettings
        self.inventoryRepository = inventoryRepository
        self.householdID = householdID
        self.chatFn = chatFn ?? { messages in
            try await AiClient.chat(settings: aiSettings, messages: messages)
        }
    }

    /// Whether the 解析 action can run (non-blank text, not already parsing).
    var canParse: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isParsing }

    /// Parses the pasted text into review-ready proposals. On success sets
    /// `proposals`; on failure sets `errorMessage` (AI error message or a friendly
    /// "no items" note) and leaves `proposals` nil.
    func parse() async {
        guard canParse else { return }
        await run(emptyMessage: String(localized: "inventory.pasteImport.textEmptyResult")) {
            try await AiIngredientParser.fromText(self.text, chatFn: self.chatFn)
        }
    }

    /// Parses a picked photo (downscaled JPEG `Data`) into review-ready proposals,
    /// driving the SAME state as the text path so the review presentation is shared.
    /// On success sets `proposals`; on failure sets `errorMessage`.
    func parseImage(_ data: Data) async {
        guard !isParsing else { return }
        await run(emptyMessage: String(localized: "inventory.pasteImport.imageEmptyResult")) {
            try await AiIngredientParser.fromImage(data, chatFn: self.chatFn)
        }
    }

    /// Shared parse → drafts → proposals pipeline for both the text and image
    /// paths. Sets `isParsing` while running, maps `AiError` to its Chinese
    /// message, and resolves drafts against live inventory via the same
    /// `IntakeProposalFactory` the manual-add flow uses.
    private func run(
        emptyMessage: String,
        parse: () async throws -> [IngredientDraft]
    ) async {
        isParsing = true
        errorMessage = nil
        proposals = nil
        defer { isParsing = false }

        let drafts: [IngredientDraft]
        do {
            drafts = try await parse()
        } catch let error as AiError {
            errorMessage = error.message
            return
        } catch {
            errorMessage = String(localized: "inventory.pasteImport.parseFailed \(error.localizedDescription)")
            return
        }

        guard !drafts.isEmpty else {
            errorMessage = emptyMessage
            return
        }

        let inventory: [Ingredient]
        do {
            inventory = try await inventoryRepository.loadAllFor(householdID)
        } catch {
            errorMessage = String(localized: "inventory.load.failedShort")
            return
        }
        proposals = IntakeProposalFactory.fromDrafts(drafts, inventory)
    }

    /// Clears the parsed result after it has been consumed (review pushed).
    func consumeProposals() {
        proposals = nil
    }
}
