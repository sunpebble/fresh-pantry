import AppIntents
import Foundation

/// Siri / 快捷指令 / Spotlight intent: 「把 X 加进购物清单」.
///
/// CONCURRENCY / CORRECTNESS DECISION — `openAppWhenRun = true`:
/// the add is intentionally NOT performed inside the intent process. The active
/// household id is resolved from the backend into the in-memory `SyncSession`
/// after sign-in and is never persisted to disk. A background container write
/// would therefore land in the local-only ("") scope and never sync to the
/// family — only join-time `adoptLocalDataIntoHousehold` migrates "" → household,
/// so a divergent local row would be silently invisible to other members. Rather
/// than ship an add that can drop the write, the intent enqueues the name
/// (`IntentPendingAddQueue`) and opens the app; the live, fully-wired
/// `ShoppingStore` drains the queue through its real `syncWriter`, guaranteeing
/// correct household scoping + outbox enqueue + sync. The Siri/Shortcuts/Spotlight
/// entry point is still delivered — the only cost is a brief app foreground.
struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.shopping.add.title"

    static let description = IntentDescription("intent.shopping.add.description")

    /// Open the app so the add runs through the live store (see type doc).
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "intent.shopping.add.parameter.title",
        description: "intent.shopping.add.parameter.description",
        requestValueDialog: IntentDialog("intent.shopping.add.request")
    )
    var itemName: String

    static var parameterSummary: some ParameterSummary {
        Summary("intent.shopping.add.summary")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Same normalization the store applies; a blank name surfaces a visible
        // error dialog (never a silent no-op).
        guard let name = IntentName.normalize(itemName) else {
            throw IntentError.emptyItemName
        }
        IntentPendingAddQueue().enqueue(name)
        // Nudge the (now-foregrounded) app to drain THIS session — the scene-phase
        // drains alone can miss when `.active` fires before this enqueue or the
        // app was already active. See `Notification.Name.intentDidEnqueueShoppingAdd`.
        NotificationCenter.default.post(name: .intentDidEnqueueShoppingAdd, object: nil)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "intent.shopping.add.dialog \(name)")))
    }
}

/// User-facing intent errors. Conforms to `CustomLocalizedStringResourceConvertible`
/// so Siri/Shortcuts speak/show the Chinese message instead of a generic failure.
enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case emptyItemName
    case noInventory

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyItemName:
            return "intent.error.emptyItemName"
        case .noInventory:
            return "intent.error.noInventory"
        }
    }
}
