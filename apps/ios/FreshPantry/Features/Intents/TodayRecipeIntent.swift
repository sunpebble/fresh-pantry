import AppIntents
import Foundation

/// Siri / 快捷指令 / Spotlight intent: 「今天做什么 / 今天吃什么」.
///
/// READ-ONLY(`openAppWhenRun = false`):读共享容器里的库存(经
/// `IntentInventoryReader`,无需 household id——见该类),用 `TodayRecipeSelector`
/// 在共享菜谱库里挑一道能用掉临期食材的菜(无临期则挑现有食材最齐的)。无
/// mutation、无 sync。后台进程拿不到 household,custom 菜谱本就不可达。
struct TodayRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.today.title"

    static let description = IntentDescription("intent.today.description")

    /// 纯读 — 就地作答,不前台唤起 app。
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = try? AppConfig.load()
        let remote = RemoteRecipeCatalog(client: SupabaseClientProvider(config: config).client)
        let catalog = await RecipeCatalogLoader.load(
            local: LocalRecipeRepository(),
            remote: remote,
            cache: RecipeCatalogCache()
        )
        let overlay = await RecipeCatalogLoader.overlay(remote: remote)
        let recipes = RecipeLocalizer.apply(overlay, to: catalog)
        // 读库存(尽力而为:容器打不开 / 读失败都退化为空库存 → selector 仍给得出
        // 一道菜谱库推荐,而不是报错——「今天做什么」永远该答得出来)。
        var inventory: [Ingredient] = []
        if let container = try? ModelContainerFactory.makeShared() {
            inventory = (try? await IntentInventoryReader(modelContainer: container).loadAllLive()) ?? []
        }
        guard let pick = TodayRecipeSelector.pick(recipes: recipes, inventory: inventory) else {
            return .result(dialog: "intent.today.empty")
        }
        return .result(dialog: IntentDialog(stringLiteral: TodayRecipeSelector.dialog(for: pick)))
    }
}
