# Remove Recipes Expiring Banner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the static, non-interactive "优先使用 N 件临期食材" banner from the Recipes screen and its now-dead supporting code.

**Architecture:** Pure deletion across three files. The banner is the only consumer of `RecipesStore.expiringItemCount` and the `recipe.list.prioritizeExpiring %lld` localization key, so all three are removed together. No new files, no new tests (the spec confirms no tests reference these symbols). Verification = clean compile + green existing test suite.

**Tech Stack:** SwiftUI, Xcode (Swift 6), String Catalog (`Localizable.xcstrings`).

## Global Constraints

- iOS app lives under `apps/ios/`; project generated from `project.yml` via XcodeGen. This change edits existing files only — **no `xcodegen generate` needed** (no files added/removed).
- Build/test commands run from `apps/ios/`.
- Conventional Commits style for the commit message (repo convention).
- Do NOT touch the 「用临期」 tab, the `RecipeCard` per-card "用临期 N" label, the Dashboard expiring surfaces, or any `RecipeMatching` ranking logic.

---

## Task 1: Remove the expiring banner, its dead store property, and its localization key

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Recipes/RecipesView.swift` (call site ~387-391, view ~714-735)
- Modify: `apps/ios/FreshPantry/Features/Recipes/RecipesStore.swift:226-228`
- Modify: `apps/ios/FreshPantry/Resources/Localizable.xcstrings:23690-23741`

**Interfaces:**
- Consumes: nothing (pure deletion).
- Produces: nothing new. After this task, `RecipesView` no longer references `expiringBanner`; `RecipesStore` no longer exposes `expiringItemCount`; the string catalog no longer has `recipe.list.prioritizeExpiring %lld`.

> **Note on testing:** This is a deletion. No tests reference `expiringBanner`, `expiringItemCount`, or the localization key (verified by grep across the repo). There is no failing test to write — verification is a clean compile plus the existing test suite passing.

- [ ] **Step 1: Remove the banner call site in `RecipesView.swift`**

In the main `VStack` of `body`, delete this block (currently between `tagChips` and `seasonalCarousel`):

```swift
                // The banner is the 用临期 tab's whole premise — only surface it as a
                // prompt on the OTHER tabs.
                if store.expiringItemCount > 0, store.tab != .expiring {
                    expiringBanner
                }
```

After deletion, the `VStack` should read straight through:

```swift
                tagChips

                timeFilterChips

                seasonalCarousel

                listBody
```

(The exact surrounding lines are `tagChips`, then the deleted banner, then `seasonalCarousel`. Keep the blank-line spacing consistent with the siblings.)

- [ ] **Step 2: Remove the `expiringBanner` view definition in `RecipesView.swift`**

Delete the entire `// MARK: 临期 banner` section and its computed view (the block that starts with `// MARK: 临期 banner` and ends after the `expiringBanner` view's closing brace). The block to remove in full:

```swift
    // MARK: 临期 banner

    /// "优先使用 N 件临期食材" prompt — surfaces the reduce-waste intent when the
    /// pantry has expiring items (mirrors the Flutter `_ExpiringBanner`).
    private var expiringBanner: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.fkDanger)
            Text(String(localized: "recipe.list.prioritizeExpiring \(store.expiringItemCount)"))
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                .fill(Color.fkWarnSoft)
        )
        .padding(.horizontal, FkSpacing.lg)
    }
```

- [ ] **Step 3: Remove the dead `expiringItemCount` property in `RecipesStore.swift`**

Delete these three lines (the doc comment + the computed property):

```swift
    /// Count of distinct expiring/expired inventory names — drives the "优先使用 N
    /// 件临期食材" banner.
    var expiringItemCount: Int { expiringNames.count }
```

After removal, `expiringUseCount(_:)` (which stays — it drives the per-card label) remains directly above, and the `// Shared catalog first...` comment block follows. Do not remove `expiringNames` itself — `expiringUseCount` still reads it.

- [ ] **Step 4: Remove the localization key in `Localizable.xcstrings`**

Delete the entire JSON entry for the key, from its opening line through the comma that closes it. The entry starts at:

```json
    "recipe.list.prioritizeExpiring %lld": {
```

and ends at the `},` immediately before the next key `    "recipe.list.searchPlaceholder": {`. The full block spans the `recipe.list.prioritizeExpiring %lld` object including its `zh-Hans`, `en` (plural), `ja`, and `fr` (plural) sub-entries. Remove it so that the entry preceding it (`recipe.list.prioritizeExpiring`'s alphabetical neighbor above) is directly followed by `recipe.list.searchPlaceholder`.

- [ ] **Step 5: Verify no dangling references remain**

Run from the repo root:

```bash
rg -n "expiringBanner|expiringItemCount|prioritizeExpiring" apps/ios
```

Expected: **no output** (zero matches). If anything remains, remove that reference too.

- [ ] **Step 6: Build to confirm it compiles**

Run from `apps/ios`:

```bash
xcodebuild build -project FreshPantry.xcodeproj -scheme FreshPantry \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. No "unused" warnings related to the removed symbols.

- [ ] **Step 7: Run the test suite**

Run from `apps/ios`:

```bash
xcodebuild test -project FreshPantry.xcodeproj -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all tests pass. (If `iPhone 17 Pro` is ambiguous — multiple runtimes — fall back to a UDID per the iOS README's troubleshooting section: `xcrun simctl list devices available | grep iPhone`, then `-destination 'platform=iOS Simulator,id=<UDID>'`.)

- [ ] **Step 8: Commit**

```bash
git add apps/ios/FreshPantry/Features/Recipes/RecipesView.swift \
        apps/ios/FreshPantry/Features/Recipes/RecipesStore.swift \
        apps/ios/FreshPantry/Resources/Localizable.xcstrings
git commit -m "fix(recipes): remove non-actionable expiring banner"
```

---

## Self-Review

**1. Spec coverage:**
- "Remove the `expiringBanner` view and its call site" → Steps 1-2. ✓
- "Remove the now-dead `RecipesStore.expiringItemCount`" → Step 3. ✓
- "Remove the unused localization key" → Step 4. ✓
- "Keep 用临期 tab / RecipeCard label / Dashboard / RecipeMatching" → Global Constraints forbid touching them. ✓
- "No test updates required" → reflected; verification is build + existing suite. ✓

**2. Placeholder scan:** No TBD/TODO; every step shows exact code/blocks to delete and exact commands with expected output. ✓

**3. Type consistency:** Only one symbol removed from the store (`expiringItemCount`); `expiringUseCount(_:)` and `expiringNames` explicitly retained. No naming drift. ✓
