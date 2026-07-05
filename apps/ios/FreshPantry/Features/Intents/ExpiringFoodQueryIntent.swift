import AppIntents
import Foundation

/// Siri / 快捷指令 / Spotlight intent: 「查临期食材 / 什么快过期了」.
///
/// READ-ONLY, so it safely runs in the background (`openAppWhenRun = false`): it
/// opens the shared on-disk container, reads every live inventory row via
/// `IntentInventoryReader` (no household id needed — see that type), and reports
/// the names expiring within the default window. No mutation, no sync, no
/// household scoping required.
struct ExpiringFoodQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.expiring.title"

    static let description = IntentDescription("intent.expiring.description")

    /// Pure read — answer in place without foregrounding the app.
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Build the SAME shared container the app persists into. If it can't be
        // opened, surface a visible error (don't fabricate an empty answer).
        guard let container = try? ModelContainerFactory.makeShared() else {
            throw IntentError.noInventory
        }
        let reader = IntentInventoryReader(modelContainer: container)
        let items = (try? await reader.loadAllLive()) ?? []
        let names = ExpiringFoodSelector.expiringNames(in: items)

        let window = ExpiringFoodSelector.defaultWithinDays
        guard !names.isEmpty else {
            return .result(dialog: IntentDialog("intent.expiring.empty"))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "intent.expiring.result \(window) \(names.joined(separator: String(localized: "household.personal.separator")))")))
    }
}
