import AppIntents

/// Exposes the app's intents to Siri / 快捷指令 / Spotlight with Chinese trigger
/// phrases. The system surfaces these automatically once the app is installed —
/// no extension target, no signing/App Group changes (the intents run in the main
/// app target).
///
/// Every `AppShortcutPhrase` MUST embed `\(.applicationName)` so Siri can scope
/// the phrase to this app; phrases without it are rejected at build time.
struct FreshPantryAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToShoppingListIntent(),
            phrases: [
                "用\(.applicationName)加到购物清单", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "在\(.applicationName)里加到购物清单", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "\(.applicationName)加购物清单", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
            ],
            shortTitle: "intent.shopping.add.title",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: ExpiringFoodQueryIntent(),
            phrases: [
                "查\(.applicationName)临期食材", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "\(.applicationName)什么快过期了", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "用\(.applicationName)看临期食材", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
            ],
            shortTitle: "intent.expiring.title",
            systemImageName: "clock.badge.exclamationmark"
        )
        AppShortcut(
            intent: TodayRecipeIntent(),
            phrases: [
                "用\(.applicationName)今天做什么", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "\(.applicationName)今天吃什么", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
                "用\(.applicationName)推荐做菜", // i18n:ignore localized Siri shortcut phrase; AppShortcutPhrase must keep applicationName interpolation
            ],
            shortTitle: "intent.today.title",
            systemImageName: "fork.knife"
        )
    }
}
