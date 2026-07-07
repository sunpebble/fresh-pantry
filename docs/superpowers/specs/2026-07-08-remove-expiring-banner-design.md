# Remove Expiring Banner Design

## Goal

Remove the static "优先使用 N 件临期食材" banner from the Recipes screen. The banner surfaces a reduce-waste intent but is non-interactive (no tap target) and recommends no specific recipe, which creates understanding cost with no payoff. The existing 「用临期」 tab is the real, actionable entry point and remains.

## Scope

Remove:

- The `expiringBanner` view and its call site in `RecipesView`.
- The now-dead `RecipesStore.expiringItemCount` computed property.
- The unused localization key `recipe.list.prioritizeExpiring %lld`.

Keep:

- The 「用临期」 tab (`RecipesStore.Tab.expiring`) and its `rankedByExpiringUse` ranking.
- The `RecipeCard` "用临期 N" per-card label (`expiringUse`), which sits on a tappable card and conveys which specific dish uses expiring items.
- The Dashboard expiring signals: the 临期 tile, the 用临期 fallback strip, and the 临期 +0.5 boost in the today recommendation.
- All `RecipeMatching` ranking logic.
- `RecipesStore.expiringUseCount(_:)` (drives the per-card label and Dashboard/MealPlan cards).

## Code Changes

### `apps/ios/FreshPantry/Features/Recipes/RecipesView.swift`

- Delete the call site (the `if store.expiringItemCount > 0, store.tab != .expiring { expiringBanner }` block) from the main `VStack`.
- Delete the `// MARK: 临期 banner` section and the `expiringBanner` computed view.

### `apps/ios/FreshPantry/Features/Recipes/RecipesStore.swift`

- Delete the `expiringItemCount` computed property and its doc comment. After the banner is gone, nothing reads it.

### `apps/ios/FreshPantry/Resources/Localizable.xcstrings`

- Delete the `"recipe.list.prioritizeExpiring %lld"` entry (zh-Hans / en plural / ja / fr plural).

### Tests

No tests reference the banner, `expiringItemCount`, or the localization key. No test updates required.

## Discoverability Impact

After removal, the Recipes screen no longer shows a count of expiring items on the 探索 / 现有 / 我的 tabs, and the 「用临期」 tab has no numeric badge. This is acceptable for a self-use app: the Dashboard still carries strong expiring signals (临期 tile + 用临期 fallback strip), and the 「用临期」 tab is always visible in the segmented picker.

## Testing

Build and run the iOS app:

```bash
xcodebuild -project apps/ios/FreshPantry.xcodeproj -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run unit tests:

```bash
xcodebuild -project apps/ios/FreshPantry.xcodeproj -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Manual verification:

- With expiring items present, the 探索 / 现有 / 我的 tabs show no banner.
- The 「用临期」 tab still lists recipes ranked by expiring use.
- Recipe cards still show the "用临期 N" label where applicable.
- No compiler warning about an unused property or string.

## Out Of Scope

- Adding a count badge to the 「用临期」 tab.
- Re-touching the Dashboard expiring surfaces.
- Changing the `RecipeCard` per-card "用临期 N" label.
- Renaming or re-ranking anything in `RecipeMatching`.
