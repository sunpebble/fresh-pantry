# Stage 3 — Decision Aids Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` syntax.
>
> **Reference docs:**
> - Roadmap memory: `memory/stage_roadmap_2026_05.md`
> - Glossary: `CONTEXT.md`
> - Stage 2 plan: `docs/superpowers/plans/2026-05-15-stage2-local-push-and-tonight-recipe.md` (built the boost-by-expiring score)

**Goal:** Close two friction loops that Stage 1+2 didn't:
1. **缺货合并 → 一键加购** — surface "frequently-bought ingredients that are now at zero" as a list, with a one-tap "add all to shopping list" action.
2. **临期兜底菜谱** — Dashboard surfaces ONE explicit "use your 临期 items today" recipe card, distinct from the existing "今日推荐", that's ranked specifically by max-expiring-coverage.

**Architecture:**
- `lowStockItemsProvider` derives "items frequently bought but currently absent" from existing `add_history` (no new persistence). Implements decision D from grilling: shortage = `add_history.count ≥ 3` AND not currently in inventory.
- `expiringFallbackRecipeProvider` re-uses `recommendedRecipesProvider` candidates but scores them by COUNT of expiring inventory items used (not the +0.5 binary boost from Stage 2 — that one only nudges ordering; this provider gives a single answer to "which recipe covers MOST 临期 items"). Returns single Top-1 recipe + list of which expiring items it would consume.
- UI changes are purely additive: 2 new Dashboard sections (low-stock + expiring fallback), 1 Inventory tab CTA. No screens replaced.

**Tech Stack:** Flutter (existing), Riverpod (existing), SharedPreferences (existing). No new pub deps.

**Non-negotiables:**
- **No new persistence keys.** Reuse `add_history`.
- **No new data model.** No `Ingredient.minQuantity`. The frequency-based shortage definition has no schema impact.
- **No AI calls in this stage.** All ranking is in-memory pure functions.
- **Stage 2 boost (+0.5 in `recommendedRecipesProvider`) stays.** The new fallback provider is parallel, not a replacement.
- **Confirm before add** for the bulk-shopping CTA — show a dialog listing items to add; user can Cancel.

**Out of scope:**
- Per-item `minQuantity` thresholds (deferred — decision D rules them out for now).
- AI-generated fallback recipes (Stage 3.5 if needed).
- Snooze / dismiss for the low-stock card.
- Notification of low-stock (Stage 2 only handles expiry — adding low-stock push is Stage 2.5).
- Multi-recipe fallback (cook-3-dishes-this-week planning is way out of scope).

---

## File Structure

| File | Responsibility | Phase |
|---|---|---|
| `lib/providers/inventory_provider.dart` (modify) | Add `lowStockItemsProvider` returning `List<FrequentItem>` filtered by absent-from-inventory | 1 |
| `lib/providers/recipe_provider.dart` (modify) | Add `expiringFallbackRecipeProvider` returning `({Recipe? recipe, Set<String> coveredNames})?` | 3 |
| `lib/widgets/dashboard/low_stock_card.dart` (create) | Dashboard card UI: "N 件库存不足" + expandable list + "一键加入购物清单" CTA | 2 |
| `lib/widgets/dashboard/expiring_fallback_card.dart` (create) | Dashboard card UI: recipe preview + "可用临期 X / Y" badge + tap → recipe_detail | 4 |
| `lib/screens/dashboard_screen.dart` (modify) | Mount the 2 new cards at appropriate positions | 2, 4 |
| `lib/screens/inventory_screen.dart` (modify) | Sticky CTA at bottom when low-stock items exist (links to dashboard card or directly fires add) | 2 |
| Tests under `test/` (create) | Provider + widget tests | all |

---

## Phase 1: Shortage detection — `lowStockItemsProvider`

### Task 1.1: Add `lowStockItemsProvider`

**Files:**
- Modify: `lib/providers/inventory_provider.dart`
- Create: `test/low_stock_items_test.dart`

`FrequentItem` already exists at `lib/models/frequent_item.dart` (used by `frequentItemsProvider`). It has `name`, `category`, `storage`, `unit`, `shelfLifeDays`, `count`. We reuse it directly.

A "low-stock item" is a `FrequentItem` where:
- `count >= 3` (bought 3+ times historically)
- AND the item's `name` (case-insensitive trimmed) is NOT in current `inventoryProvider` as any row.

This decouples from `Ingredient.quantity` parsing (which is freeform String) — we only check name presence.

- [ ] **Step 1: Write failing test**

```dart
// test/low_stock_items_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  required Map<String, Object> history,
  required List<Ingredient> inventory,
}) async {
  SharedPreferences.setMockInitialValues({
    'add_history': '$history',
  });
  final prefs = await SharedPreferences.getInstance();
  // Write the history map as proper JSON.
  await prefs.setString('add_history',
      Iterable.castFrom([]).fold('', (_, __) => '') // placeholder — we set below
  );
  // Actually: use jsonEncode here.
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(inventory),
  ]);
}

Ingredient _ing(String name) => Ingredient(
      name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      category: FoodCategories.other, storage: IconType.fridge,
    );

void main() {
  // NOTE: write the prefs setup helper with jsonEncode for `add_history`.
  // The implementer should rewrite the _container helper to:
  //   - Take a `Map<String, dynamic> history` 
  //   - jsonEncode it and use SharedPreferences.setMockInitialValues({'add_history': encoded})
  //   - Override inventorySeedProvider

  test('returns frequent items not currently in inventory', () async {
    // history: 米 bought 5×, 鸡蛋 bought 3×, 葱 bought 2×
    // inventory: 米 present, 鸡蛋 absent, 葱 absent
    // expected: 鸡蛋 (frequent + absent). 葱 excluded (count < 3). 米 excluded (in inventory).
    // The test body itself uses the helper described above.
    // PLACEHOLDER — see implementer note below.
  }, skip: 'Implementer: rewrite helper with jsonEncode, then enable.');
}
```

> IMPLEMENTER NOTE: the test scaffold above is intentionally rough. Rewrite the `_container` helper to use `jsonEncode` for the `add_history` map. Test cases to write:
>
> 1. `'returns frequent items not currently in inventory'` — history has 米(5×), 鸡蛋(3×), 葱(2×); inventory has 米; expected output = [鸡蛋] (葱 excluded by count<3, 米 excluded by being in inventory).
> 2. `'empty history returns empty'`.
> 3. `'name matching is case + whitespace insensitive'` — history has `'鸡蛋'`, inventory has `' 鸡蛋 '`; expected: not in low-stock list.
> 4. `'sorted by count descending'` — history: A(5), B(3), C(4); none in inventory; expected order [A, C, B].

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

Add to `lib/providers/inventory_provider.dart` after the existing `frequentItemsProvider`:

```dart
/// Items the user has bought >=3 times historically but which are NOT currently
/// in inventory (by name, case+whitespace insensitive). Sorted by historical
/// frequency descending.
final lowStockItemsProvider = Provider<List<FrequentItem>>((ref) {
  final frequent = ref.watch(frequentItemsProvider);
  final inventory = ref.watch(inventoryProvider);
  final presentNames = inventory
      .map((i) => i.name.trim().toLowerCase())
      .toSet();

  final filtered = frequent
      .where((f) => f.count >= 3)
      .where((f) => !presentNames.contains(f.name.trim().toLowerCase()))
      .toList();
  filtered.sort((a, b) => b.count.compareTo(a.count));
  return filtered;
});
```

> NOTE: `frequentItemsProvider` (existing) already returns only items with count >= 2 limited to top 6. To get items with count >= 3, you may need to either:
> (a) raise the threshold in `frequentItemsProvider` from 2 to 3, OR
> (b) add an internal helper that exposes the full history (no top-6 cap, lower threshold), and have `lowStockItemsProvider` use that.
>
> Read the existing implementation first. Option (b) is cleaner since `frequentItemsProvider` caps at top 6 — that's wrong for low-stock detection (we want ALL frequent items absent, not just top 6).
>
> CONCRETE FIX: extract the history-reading logic into a private helper `_allFrequentItemsFromHistory(prefs, addHistoryVersionProvider)` that returns the unfiltered list. Have both `frequentItemsProvider` and `lowStockItemsProvider` consume the helper.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/inventory_provider.dart test/low_stock_items_test.dart
git commit -m "feat(inventory): lowStockItemsProvider derives 'frequently-bought, currently-absent' items"
```

---

## Phase 2: 缺货 UI — Dashboard card + Inventory CTA

### Task 2.1: `LowStockCard` Dashboard widget

**Files:**
- Create: `lib/widgets/dashboard/low_stock_card.dart`
- Create: `test/low_stock_card_test.dart`

The card:
- Hidden when `lowStockItemsProvider` is empty.
- Title: "库存不足 (N 项)" with leading icon.
- Body: vertical list of items (CatIcon + name + 已买 N 次)
- Bottom CTA: `FilledButton`, key `low_stock_bulk_add_cta`, label "全部加入购物清单 (N)"
- onTap: show confirm dialog (list items + 取消 / 确认加入)，confirm → call `shoppingProvider.notifier.addFromSuggestion(name)` for each item → Toast "已加入 N 项".

- [ ] **Step 1: Implement widget** (uses ConsumerWidget pattern matching existing dashboard cards like `_ExpiringScroller`).

Reference layout: see `lib/widgets/dashboard/expiring_card.dart` or similar for FK style. Use `FkCard` for the container. Title row uses `FkSectionHead` pattern.

```dart
// lib/widgets/dashboard/low_stock_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/frequent_item.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/fk_toast.dart';
import '../shared/cat_icon.dart';
import '../shared/fk_card.dart';

class LowStockCard extends ConsumerWidget {
  const LowStockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lowStockItemsProvider);
    if (items.isEmpty) return const SizedBox.shrink();

    return FkCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: AppColors.fkWarn, size: 20),
              const SizedBox(width: 8),
              Text(
                '库存不足 (${items.length} 项)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items.take(4)) _LowStockRow(item: item),
          if (items.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '+ 还有 ${items.length - 4} 项',
                style: const TextStyle(
                  fontSize: 12, color: AppColors.outline,
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('low_stock_bulk_add_cta'),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text('全部加入购物清单 (${items.length})'),
              onPressed: () => _confirmBulkAdd(context, ref, items),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBulkAdd(
    BuildContext context,
    WidgetRef ref,
    List<FrequentItem> items,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('加入购物清单 (${items.length} 项)?'),
        content: Text(
          items.map((i) => '${i.name} (已买 ${i.count} 次)').join('\n'),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认加入'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final shopping = ref.read(shoppingProvider.notifier);
    var addedCount = 0;
    for (final item in items) {
      final added = await shopping.addFromSuggestion(item.name);
      if (added) addedCount++;
    }
    if (!context.mounted) return;
    fkToast(context, '已加入 $addedCount 项到购物清单');
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item});
  final FrequentItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CatIcon(category: _catIdFor(item.category), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text('已买 ${item.count} 次',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.outline,
              )),
        ],
      ),
    );
  }

  // Match the FK category → cat icon string. There's an existing helper for
  // this in `lib/widgets/shared/category_icon.dart` — use it.
  String _catIdFor(String? category) {
    // INLINE: see lib/widgets/shared/category_icon.dart's _fkCatIdFor.
    // Replicate here or extract into a shared utility.
    return 'grain';
  }
}
```

> IMPLEMENTER NOTE: replace the placeholder `_catIdFor` with the real mapping. If `lib/widgets/shared/category_icon.dart` exposes a top-level `fkCatIdFor(String?)` function, import + use it. If it's private (`_fkCatIdFor`), promote it to public-with-leading-letter `fkCatIdFor` and export.

- [ ] **Step 2: Widget test** verifying:
  - empty `lowStockItemsProvider` → renders `SizedBox.shrink`
  - non-empty → renders with CTA button having the right label
  - tap CTA → confirm dialog appears
  - tap "确认加入" → shopping provider receives N adds (use a probe via `ref.read(shoppingProvider).length` before/after)

- [ ] **Step 3: Run + commit**

```bash
git add lib/widgets/dashboard/low_stock_card.dart test/low_stock_card_test.dart
git commit -m "feat(dashboard): LowStockCard with bulk-add CTA"
```

---

### Task 2.2: Mount LowStockCard in Dashboard

**File:**
- Modify: `lib/screens/dashboard_screen.dart`

Insert `const LowStockCard()` in the Dashboard's ListView/Column at the appropriate position. Suggested spot: between the "该用了" (expiring) section and the "今日推荐" (today's recipe) section. Wrap in a `Padding` matching surrounding sections.

- [ ] **Step 1: Edit**

Find the section where existing cards are stacked. Insert:

```dart
const Padding(
  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
  child: LowStockCard(),
),
```

Add import: `import '../widgets/dashboard/low_stock_card.dart';`

- [ ] **Step 2: `flutter analyze` 0 errors. `flutter test` green.**

- [ ] **Step 3: Commit**

```bash
git add lib/screens/dashboard_screen.dart
git commit -m "feat(dashboard): mount LowStockCard between 该用了 and 今日推荐"
```

---

### Task 2.3: Inventory tab — bottom CTA when low-stock items exist

**File:**
- Modify: `lib/screens/inventory_screen.dart`

When `lowStockItemsProvider.isNotEmpty`, show a sticky bottom CTA `"补货 N 项"` that links to the Dashboard low-stock card (or directly fires the same bulk-add flow).

Simplest implementation: directly fire the same bulk-add flow. Reuse the confirm-dialog helper from `LowStockCard` by extracting it into a top-level function `runBulkLowStockAdd(BuildContext, WidgetRef, List<FrequentItem>)` in `low_stock_card.dart`, exposed for the screen to call.

- [ ] **Step 1: Extract `runBulkLowStockAdd` from LowStockCard into a top-level function**

Move the `_confirmBulkAdd` logic into:

```dart
Future<void> runBulkLowStockAdd(
  BuildContext context,
  WidgetRef ref,
  List<FrequentItem> items,
) async {
  // ... existing body
}
```

Have `LowStockCard._confirmBulkAdd` call this top-level function.

- [ ] **Step 2: Add CTA to InventoryScreen**

In `inventory_screen.dart`, inside the Scaffold, when `lowStockItems` is non-empty (read via `ref.watch(lowStockItemsProvider)`), add a `Positioned` bottom sticky button (or wrap body in Column with bottom bar):

```dart
final lowStock = ref.watch(lowStockItemsProvider);
// ...
if (lowStock.isNotEmpty)
  SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: FilledButton.icon(
      key: const Key('inventory_low_stock_cta'),
      icon: const Icon(Icons.add_shopping_cart, size: 18),
      label: Text('补货 ${lowStock.length} 项'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
      onPressed: () => runBulkLowStockAdd(context, ref, lowStock),
    ),
  ),
```

> NOTE: this might conflict with the existing "合并 N 批" CTA (Stage 1.6.1). Both can't be simultaneously visible. Resolve: prefer the "合并" CTA when in selection mode (so user is explicitly multi-selecting), otherwise show the "补货" CTA.

- [ ] **Step 3: Widget test verifying CTA appears + tap fires bulk-add flow**

- [ ] **Step 4: Run + commit**

```bash
git add lib/screens/inventory_screen.dart lib/widgets/dashboard/low_stock_card.dart \
        test/inventory_low_stock_cta_test.dart
git commit -m "feat(inventory): 补货 N 项 sticky CTA when low-stock items exist"
```

---

## Phase 3: Expiring fallback recipe — `expiringFallbackRecipeProvider`

### Task 3.1: Provider returning Top-1 recipe by expiring-coverage

**Files:**
- Modify: `lib/providers/recipe_provider.dart`
- Create: `test/expiring_fallback_recipe_test.dart`

A new provider `expiringFallbackRecipeProvider` returns:

```dart
({Recipe recipe, Set<String> coveredExpiringNames})?
```

(or `null` when no expiring items OR no recipe uses any of them).

Algorithm:
1. Compute `expiringNameSet = inventory.where(state in {expiringSoon, expired}).map(name).toSet()` (existing, lifted from Stage 2 boost).
2. If `expiringNameSet.isEmpty` → return null.
3. From all candidate recipes (base + custom, same source as `recommendedRecipesProvider`), score each by **count of expiring names matched** (NOT proportion — absolute count).
4. Tie-break: prefer recipes with higher matched-fresh ingredients too (more cookable).
5. Return Top-1 only if its expiring-coverage ≥ 1.

Result is `(recipe, coveredExpiringNames)` for UI display.

- [ ] **Step 1: Tests**

```dart
// test/expiring_fallback_recipe_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ingredient _ing({
  required String name,
  FreshnessState state = FreshnessState.fresh,
}) =>
    Ingredient(
      name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: state == FreshnessState.fresh ? 1.0 : 0.2,
      state: state,
      category: FoodCategories.other,
      storage: IconType.fridge,
    );

Recipe _recipe(String id, List<String> ings) => Recipe(
      id: id, name: id, category: '中餐',
      difficulty: 1, cookingMinutes: 10, description: '',
      ingredients: ings
          .map((n) => RecipeIngredient(name: n, quantity: '1', unit: '个'))
          .toList(),
      steps: const [],
    );

Future<ProviderContainer> _container({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(inventory),
    recipesProvider.overrideWith((ref) => Future.value(recipes)),
  ]);
  await c.read(recipesProvider.future);
  return c;
}

void main() {
  test('returns null when no expiring items', () async {
    final c = await _container(
      inventory: [_ing(name: '苹果')],
      recipes: [_recipe('a', ['苹果'])],
    );
    expect(c.read(expiringFallbackRecipeProvider), isNull);
  });

  test('returns recipe covering most expiring items', () async {
    final inventory = [
      _ing(name: '番茄', state: FreshnessState.expiringSoon),
      _ing(name: '鸡蛋', state: FreshnessState.expiringSoon),
      _ing(name: '黄瓜', state: FreshnessState.fresh),
    ];
    final recipes = [
      _recipe('a', ['番茄', '鸡蛋']),       // covers 2 expiring
      _recipe('b', ['番茄', '黄瓜']),        // covers 1 expiring
      _recipe('c', ['黄瓜']),               // covers 0
    ];
    final c = await _container(inventory: inventory, recipes: recipes);
    final result = c.read(expiringFallbackRecipeProvider);
    expect(result, isNotNull);
    expect(result!.recipe.id, 'a');
    expect(result.coveredExpiringNames, {'番茄', '鸡蛋'});
  });

  test('returns null when no recipe covers any expiring item', () async {
    final inventory = [_ing(name: '番茄', state: FreshnessState.expiringSoon)];
    final recipes = [_recipe('a', ['苹果'])];
    final c = await _container(inventory: inventory, recipes: recipes);
    expect(c.read(expiringFallbackRecipeProvider), isNull);
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

Append to `lib/providers/recipe_provider.dart`:

```dart
/// Returns the single recipe that covers the most expiring inventory items,
/// along with the set of expiring names it would use. Returns null when:
/// - inventory has no expiring/expired items, OR
/// - no recipe matches any expiring item.
final expiringFallbackRecipeProvider =
    Provider<({Recipe recipe, Set<String> coveredExpiringNames})?>((ref) {
  final inventory = ref.watch(inventoryProvider);
  final expiringNameSet = inventory
      .where((i) =>
          i.state == FreshnessState.expiringSoon ||
          i.state == FreshnessState.expired)
      .map((i) => i.name.trim().toLowerCase())
      .toSet();
  if (expiringNameSet.isEmpty) return null;

  final recipesAsync = ref.watch(recipesProvider);
  final customRecipes = ref.watch(customRecipesProvider);
  final base = recipesAsync.maybeWhen(data: (d) => d, orElse: () => const <Recipe>[]);
  final seen = base.map((r) => r.id).toSet();
  final all = [...base, ...customRecipes.where((r) => !seen.contains(r.id))];

  ({Recipe recipe, Set<String> covered})? best;
  for (final recipe in all) {
    final covered = <String>{};
    for (final ri in recipe.ingredients) {
      final n = ri.name.trim().toLowerCase();
      if (expiringNameSet.contains(n)) covered.add(n);
    }
    if (covered.isEmpty) continue;
    if (best == null || covered.length > best.covered.length) {
      best = (recipe: recipe, covered: covered);
    }
  }
  if (best == null) return null;
  return (recipe: best.recipe, coveredExpiringNames: best.covered);
});
```

- [ ] **Step 4: Run** — PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/providers/recipe_provider.dart test/expiring_fallback_recipe_test.dart
git commit -m "feat(recipes): expiringFallbackRecipeProvider — Top-1 by expiring coverage"
```

---

## Phase 4: Dashboard 兜底卡 — `ExpiringFallbackCard`

### Task 4.1: Implement `ExpiringFallbackCard`

**Files:**
- Create: `lib/widgets/dashboard/expiring_fallback_card.dart`
- Create: `test/expiring_fallback_card_test.dart`

The card:
- Hidden when `expiringFallbackRecipeProvider` is null.
- Title: "用临期食材"
- Body: recipe placeholder image + recipe name + "可用 N 件临期食材" badge + horizontal pill chips for covered expiring names.
- Tap → push `RecipeDetailScreen(recipe: ...)`.

Layout inspired by `lib/widgets/recipe_card.dart` (look at it first). Use horizontal layout with placeholder on left, content on right.

- [ ] **Step 1: Implement**

```dart
// lib/widgets/dashboard/expiring_fallback_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/recipe_provider.dart';
import '../../screens/recipe_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../shared/fk_card.dart';
import '../shared/pill_chip.dart';

class ExpiringFallbackCard extends ConsumerWidget {
  const ExpiringFallbackCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(expiringFallbackRecipeProvider);
    if (result == null) return const SizedBox.shrink();
    final recipe = result.recipe;
    final covered = result.coveredExpiringNames;

    return FkCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: AppColors.fkWarnSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_fire_department,
                color: AppColors.fkWarn, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '用临期食材',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.fkWarn,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recipe.name,
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可用 ${covered.length} 件临期食材',
                  style: const TextStyle(
                    fontSize: 12, color: AppColors.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4, runSpacing: 4,
                  children: covered
                      .take(3)
                      .map((name) => PillChip(
                            label: name,
                            backgroundColor: AppColors.fkWarnSoft,
                            foregroundColor: AppColors.onSecondaryContainer,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

> NOTE: `PillChip` arguments may differ — check existing usages in the codebase. Adapt as needed.

- [ ] **Step 2: Widget test** asserting:
  - null fallback → SizedBox.shrink (or no card found)
  - non-null fallback → card visible with recipe name + "可用 N 件临期食材"

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/dashboard/expiring_fallback_card.dart test/expiring_fallback_card_test.dart
git commit -m "feat(dashboard): ExpiringFallbackCard — recipe that covers most 临期 items"
```

---

### Task 4.2: Mount `ExpiringFallbackCard` in Dashboard

**File:**
- Modify: `lib/screens/dashboard_screen.dart`

Insert `const ExpiringFallbackCard()` in the Dashboard's vertical layout. Suggested spot: between the LowStockCard (Task 2.2) and the existing "今日推荐" section. The card auto-hides when empty.

- [ ] **Step 1: Edit + import**

- [ ] **Step 2: `flutter analyze` + `flutter test`**

- [ ] **Step 3: Commit**

```bash
git add lib/screens/dashboard_screen.dart
git commit -m "feat(dashboard): mount ExpiringFallbackCard above 今日推荐"
```

---

## Phase 5: Integration + verification

### Task 5.1: Full `flutter test` + `flutter analyze`

- [ ] Run `flutter test` — expect 395 + new tests, all green.
- [ ] Run `flutter analyze` — expect 0 errors.

### Task 5.2: Manual smoke

`flutter run -d ios`. Verify:
- Add 4 ingredients then delete them → `add_history` count rises → those 4 reappear in `LowStockCard` (since now absent from inventory)
- Tap "全部加入购物清单 (4)" → confirm → switch to shopping tab → 4 items appear
- Manually mark 2 inventory items as expiring (or wait for their state to flip) → ExpiringFallbackCard appears with a recipe that uses those 2
- Tap card → navigates to recipe_detail with that recipe

---

## Self-Review

**Spec coverage:**
- ✅ Decision D (frequency-based shortage) — `lowStockItemsProvider` reads `add_history` (no new persistence)
- ✅ Decision A (max-expiring-coverage from existing recipes) — `expiringFallbackRecipeProvider`
- ✅ Dashboard cards: LowStockCard + ExpiringFallbackCard
- ✅ Inventory bottom CTA for shortage
- ✅ No AI calls, no new persistence keys, no schema changes

**Placeholder scan:**
- Task 2.1 `_catIdFor` is annotated as placeholder — implementer must wire actual mapping from `category_icon.dart`.
- Task 1.1 test scaffold's `_container` helper has a placeholder; implementer rewrites with `jsonEncode`. Clear note in plan.

**Type consistency:**
- `FrequentItem` (existing) used by `lowStockItemsProvider`, `LowStockCard`, `runBulkLowStockAdd`.
- `expiringFallbackRecipeProvider` returns `({Recipe recipe, Set<String> coveredExpiringNames})?` — used in `ExpiringFallbackCard`.
- `shoppingProvider.notifier.addFromSuggestion(name)` — existing API on `ShoppingNotifier`.

**Risk register:**
- **`frequentItemsProvider` currently caps at top 6 + count ≥ 2.** lowStockItemsProvider needs count ≥ 3 AND no top-6 cap. Mitigation: extract shared private helper. Implementer task 1.1 has explicit note.
- **`addFromSuggestion` returns false when duplicate name exists in shopping list.** Counting `addedCount` correctly handles this — the toast says "已加入 N 项" reflecting actual adds.
- **InventoryScreen has multiple CTAs** (merge-batches + low-stock). Need ordering rule: merge-batches takes precedence when in selection mode.
- **No widget test for FkToast** — toast assertion may need `pumpAndSettle` + `find.byText`. Acceptable for self-use.

---

## Out of plan — Stage 3.5 backlog

- Per-item `minQuantity` threshold (decision B from grilling, rejected for Stage 3).
- AI-generated fallback recipe (decision B from grilling decision 2, deferred).
- Low-stock push notification (deferred — Stage 2 only covers expiry pushes).
- Multi-recipe weekly planner.
- "Why this recipe" rationale text on ExpiringFallbackCard hover.
