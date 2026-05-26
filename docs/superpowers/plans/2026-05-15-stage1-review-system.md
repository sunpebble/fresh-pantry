# Stage 1 — Review System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Reference docs:**
> - Glossary: `CONTEXT.md` (Ingredient / Batch / Perishable / Intake / Deduction / Proposal / Review)
> - Architecture decision: `docs/adr/0001-inventory-row-identity.md`
> - Project mode + roadmap: `memory/project_mode_self_use.md`, `memory/stage_roadmap_2026_05.md`

**Goal:** Build the unified Review system that turns three distinct user actions — **粘贴清单 / 已购买的项一键入库 / 做完这道菜** — into reviewed, single-confirm mutations against inventory. Every inflight change funnels through a Review screen with hybrid edit UX (qty / shelfLife inline; unit / category / storage via bottom-sheet; name inline TextField).

**Architecture:**
- A sealed `Proposal` hierarchy: `IntakeProposal` (new row OR merge into existing) and `DeductionProposal` (reduce qty on existing row OR skip).
- Two `Review` screens, both built from the same widget set in `lib/widgets/review/`: `IntakeReviewScreen` (handles paste + shopping flows) and `DeductionReviewScreen` (handles recipe-completion flow).
- `InventoryNotifier` grows `applyIntakeProposals` and `applyDeductionProposals` methods that mutate state atomically.
- Merge rule γ from `ADR-0001` is implemented in a pure helper, used by all proposal-source flows.

**Tech Stack:** Flutter (existing), Riverpod (existing), SharedPreferences (existing). No new pub deps.

**Non-negotiables:**
- Three trigger sources, one mental model (Proposal → Review → Apply). No bespoke alternate flows.
- Quantity remains `String` on `Ingredient` (existing field) — we do NOT migrate the model to numeric in this plan. Stepper logic parses on edit and writes back as string.
- Backwards-compatible JSON shape on `Ingredient` / `ShoppingItem` — no breaking changes to prefs.
- Merge rule γ: Perishables → new Batch (default), Non-perishables → merge by name + unit + storage; user can always override via the row's action chip.

**Out of scope:**
- Push notifications, family sharing, decision-aid recipes (Stages 2-4).
- Unit conversion (`50g` vs `1把`). Deduction proposals show suggested deduction qty as a stepper; cross-unit mismatch is flagged visually and the user decides.
- Refactoring `ai_draft_provider` to support multi-source state — `IntakeReviewState` is a sibling state, not a replacement.

---

## File Structure

| File | Responsibility | Phase |
|---|---|---|
| `lib/data/food_categories.dart` (modify) | Add `isPerishable(category)` static helper. | 1 |
| `lib/models/proposal.dart` (create) | Sealed `Proposal` hierarchy: `IntakeProposal`, `DeductionProposal`, `IntakeAction` enum, `DeductionAction` enum. | 1 |
| `lib/services/proposal_planner.dart` (create) | Pure functions: `computeIntakeDefaultAction(...)`, `fuzzyMatchInventoryRows(...)`. | 1, 5 |
| `lib/providers/inventory_provider.dart` (modify) | `applyIntakeProposals` and `applyDeductionProposals` methods. | 1 |
| `lib/providers/intake_review_provider.dart` (create) | `IntakeReviewState` + `IntakeReviewNotifier`; draft persistence to prefs (`intake_review_draft` key). | 3 |
| `lib/providers/deduction_review_provider.dart` (create) | `DeductionReviewState` + `DeductionReviewNotifier`. | 5 |
| `lib/widgets/review/provenance_badge.dart` (create) | AI / 手改 origin dot. | 2 |
| `lib/widgets/review/inline_number_stepper.dart` (create) | -/+ stepper widget (used for qty + shelfLife). | 2 |
| `lib/widgets/review/picker_sheet.dart` (create) | Generic bottom-sheet picker (unit / category / storage). | 2 |
| `lib/widgets/review/action_chip.dart` (create) | Tap-to-switch chip (Intake: 新建 ↔ 合并 X; Deduction: 扣 ↔ 跳过). | 2 |
| `lib/widgets/review/proposal_row.dart` (create) | Per-row assembler — composes the above into a row. | 2 |
| `lib/widgets/review/review_bottom_bar.dart` (create) | Sticky CTA with select-all toggle + count + confirm. | 2 |
| `lib/screens/intake_review_screen.dart` (create) | The unified Intake Review screen (paste + shopping). | 3 |
| `lib/screens/deduction_review_screen.dart` (create) | The Deduction Review screen (cook). | 5 |
| `lib/screens/add_ingredient_screen.dart` (modify) | Add "粘贴清单" entry button. | 3 |
| `lib/screens/shopping_list_screen.dart` (modify) | Add "已购买的 N 项一键入库" sticky CTA. | 4 |
| `lib/screens/recipe_detail_screen.dart` (modify) | Add "我做了" button. | 5 |
| `lib/screens/ingredient_draft_review_screen.dart` (delete) | Replaced by `IntakeReviewScreen` once paste flow ships. | 3 |
| `lib/screens/inventory_screen.dart` (modify) | Long-press multi-select → "合并这两批" menu. | 6 |
| Tests under `test/` (create) | Per-task widget + unit tests. | all |

---

## Phase 1: Domain Foundation

### Task 1.1: Add `isPerishable` to FoodCategories

**Files:**
- Modify: `lib/data/food_categories.dart`
- Create: `test/food_categories_perishable_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/food_categories_perishable_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';

void main() {
  group('FoodCategories.isPerishable', () {
    test('果蔬生鲜 / 肉类海鲜 / 乳品蛋类 are perishable', () {
      expect(FoodCategories.isPerishable(FoodCategories.freshProduce), isTrue);
      expect(FoodCategories.isPerishable(FoodCategories.meatAndSeafood), isTrue);
      expect(FoodCategories.isPerishable(FoodCategories.dairyAndEggs), isTrue);
    });

    test('香料草本 / 其他 are non-perishable', () {
      expect(FoodCategories.isPerishable(FoodCategories.herbsAndSpices), isFalse);
      expect(FoodCategories.isPerishable(FoodCategories.other), isFalse);
    });

    test('null / unknown defaults to non-perishable (safe default)', () {
      expect(FoodCategories.isPerishable(null), isFalse);
      expect(FoodCategories.isPerishable('garbage'), isFalse);
    });

    test('normalises aliases before checking (e.g. 蔬菜 → 果蔬生鲜)', () {
      expect(FoodCategories.isPerishable('蔬菜'), isTrue);
      expect(FoodCategories.isPerishable('肉类'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/food_categories_perishable_test.dart`
Expected: FAIL — `isPerishable` undefined.

- [ ] **Step 3: Implement**

Add inside class `FoodCategories` in `lib/data/food_categories.dart`:

```dart
  /// Perishable categories track each Intake as a new Batch (per ADR-0001).
  /// Non-perishable categories merge by name+unit+storage.
  static const _perishable = {
    freshProduce,
    meatAndSeafood,
    dairyAndEggs,
  };

  static bool isPerishable(String? category) {
    final normalized = normalize(category);
    if (normalized == null) return false;
    return _perishable.contains(normalized);
  }
```

- [ ] **Step 4: Run test**

Run: `flutter test test/food_categories_perishable_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/food_categories.dart test/food_categories_perishable_test.dart
git commit -m "feat(domain): mark categories perishable per ADR-0001"
```

---

### Task 1.2: Define `Proposal` sealed hierarchy

**Files:**
- Create: `lib/models/proposal.dart`
- Create: `test/proposal_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/proposal_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  group('IntakeProposal', () {
    test('defaults action to newRow with no merge target', () {
      final p = IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      );
      expect(p.action, IntakeAction.newRow);
      expect(p.mergeTargetId, isNull);
      expect(p.selected, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      final p = IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      );
      final p2 = p.copyWith(quantity: '7', userEdited: true);
      expect(p2.quantity, '7');
      expect(p2.name, '苹果');
      expect(p2.userEdited, isTrue);
    });
  });

  group('DeductionProposal', () {
    test('defaults action to deduct with first candidate chosen', () {
      final p = DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '50g',
        candidates: const [
          DeductionCandidate(
              inventoryRowIndex: 2, displayLabel: '葱 1把 (剩 5 天)'),
        ],
        chosenIndex: 2,
        deductAmount: '1',
      );
      expect(p.action, DeductionAction.deduct);
      expect(p.chosenIndex, 2);
    });

    test('action=skip when no candidates', () {
      final p = DeductionProposal.empty(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '50g',
      );
      expect(p.action, DeductionAction.skip);
      expect(p.candidates, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/proposal_test.dart`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement**

```dart
// lib/models/proposal.dart
import 'storage_area.dart';

enum IntakeAction { newRow, mergeInto }
enum DeductionAction { deduct, skip }

/// Source of a Proposal field's value — used by the Review UI to render origin
/// dots and to know whether the user has touched a value.
enum FieldOrigin { ai, system, user }

sealed class Proposal {
  Proposal({required this.id, this.selected = true});
  final String id;
  final bool selected;
}

class IntakeProposal extends Proposal {
  IntakeProposal({
    required super.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    this.action = IntakeAction.newRow,
    this.mergeTargetId,
    this.mergeTargetLabel,
    this.origin = FieldOrigin.ai,
    this.userEdited = false,
    super.selected,
  });

  final String name;
  final String quantity;
  final String unit;
  final String? category;
  final IconType storage;
  final int? shelfLifeDays;

  final IntakeAction action;

  /// Set when [action] == [IntakeAction.mergeInto]; references the inventory
  /// row to merge into. `mergeTargetId` corresponds to the inventory list index
  /// at the time the Proposal was computed (callers must re-resolve before
  /// applying to defend against list reordering).
  final String? mergeTargetId;
  final String? mergeTargetLabel;

  /// Origin of the data before user edits; set to [FieldOrigin.ai] for AI
  /// parses, [FieldOrigin.system] for shopping-derived proposals.
  final FieldOrigin origin;

  /// True after the user touches any field in the Review screen.
  final bool userEdited;

  IntakeProposal copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? category,
    IconType? storage,
    int? shelfLifeDays,
    IntakeAction? action,
    String? mergeTargetId,
    String? mergeTargetLabel,
    bool? selected,
    bool? userEdited,
  }) {
    return IntakeProposal(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      storage: storage ?? this.storage,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
      action: action ?? this.action,
      mergeTargetId: mergeTargetId ?? this.mergeTargetId,
      mergeTargetLabel: mergeTargetLabel ?? this.mergeTargetLabel,
      origin: origin,
      userEdited: userEdited ?? this.userEdited,
      selected: selected ?? this.selected,
    );
  }
}

class DeductionCandidate {
  const DeductionCandidate({
    required this.inventoryRowIndex,
    required this.displayLabel,
  });
  final int inventoryRowIndex;
  final String displayLabel;
}

class DeductionProposal extends Proposal {
  DeductionProposal({
    required super.id,
    required this.recipeIngredientName,
    required this.requiredQty,
    required this.candidates,
    required this.chosenIndex,
    required this.deductAmount,
    this.action = DeductionAction.deduct,
    super.selected,
  });

  factory DeductionProposal.empty({
    required String id,
    required String recipeIngredientName,
    required String requiredQty,
  }) =>
      DeductionProposal(
        id: id,
        recipeIngredientName: recipeIngredientName,
        requiredQty: requiredQty,
        candidates: const [],
        chosenIndex: -1,
        deductAmount: '0',
        action: DeductionAction.skip,
        selected: false,
      );

  final String recipeIngredientName;
  final String requiredQty;
  final List<DeductionCandidate> candidates;

  /// The currently chosen inventory row's index. -1 when [action]=skip.
  final int chosenIndex;

  /// Quantity to deduct, as a string (matches `Ingredient.quantity` shape).
  final String deductAmount;

  final DeductionAction action;

  DeductionProposal copyWith({
    int? chosenIndex,
    String? deductAmount,
    DeductionAction? action,
    bool? selected,
  }) {
    return DeductionProposal(
      id: id,
      recipeIngredientName: recipeIngredientName,
      requiredQty: requiredQty,
      candidates: candidates,
      chosenIndex: chosenIndex ?? this.chosenIndex,
      deductAmount: deductAmount ?? this.deductAmount,
      action: action ?? this.action,
      selected: selected ?? this.selected,
    );
  }
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/proposal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/proposal.dart test/proposal_test.dart
git commit -m "feat(domain): add Proposal sealed hierarchy (Intake + Deduction)"
```

---

### Task 1.3: `proposal_planner` — `computeIntakeDefaultAction` (merge rule γ)

**Files:**
- Create: `lib/services/proposal_planner.dart`
- Create: `test/proposal_planner_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/proposal_planner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/proposal_planner.dart';

Ingredient _ing({
  required String name,
  String quantity = '1',
  String unit = '个',
  String? category,
  IconType storage = IconType.fridge,
}) =>
    Ingredient(
      name: name,
      quantity: quantity,
      unit: unit,
      imageUrl: '',
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
      category: category,
      storage: storage,
    );

void main() {
  group('ProposalPlanner.computeIntakeDefaultAction', () {
    test('non-perishable + name+unit+storage match → mergeInto', () {
      final inventory = [
        _ing(name: '米', unit: 'kg', category: FoodCategories.other),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.mergeInto);
      expect(action.targetIndex, 0);
    });

    test('perishable + match → newRow (default to new Batch)', () {
      final inventory = [
        _ing(name: '牛奶', unit: '盒', category: FoodCategories.dairyAndEggs),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '牛奶',
          unit: '盒',
          storage: IconType.fridge,
          category: FoodCategories.dairyAndEggs,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
      expect(action.targetIndex, isNull);
    });

    test('different unit → newRow (no merge across units)', () {
      final inventory = [
        _ing(name: '葱', unit: '把', category: FoodCategories.freshProduce),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '葱',
          unit: 'g',
          storage: IconType.fridge,
          category: FoodCategories.freshProduce,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
    });

    test('different storage → newRow', () {
      final inventory = [
        _ing(
            name: '苹果',
            unit: '个',
            category: FoodCategories.other,
            storage: IconType.fridge),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '苹果',
          unit: '个',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
    });

    test('no inventory → newRow', () {
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: const [],
      );
      expect(action.kind, IntakeAction.newRow);
    });
  });
}

class _IntakeCandidate implements IntakeCandidate {
  _IntakeCandidate({
    required this.name,
    required this.unit,
    required this.storage,
    required this.category,
  });
  @override
  final String name;
  @override
  final String unit;
  @override
  final IconType storage;
  @override
  final String? category;
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/proposal_planner_test.dart`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement**

```dart
// lib/services/proposal_planner.dart
import '../data/food_categories.dart';
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';

/// Minimal duck-typed view of an intake's identity fields. Both
/// `IngredientDraft` (paste flow) and `ShoppingItem` (shopping flow) can
/// implement this on the fly when calling [ProposalPlanner].
abstract class IntakeCandidate {
  String get name;
  String get unit;
  IconType get storage;
  String? get category;
}

class IntakeDefaultAction {
  const IntakeDefaultAction.newRow()
      : kind = IntakeAction.newRow,
        targetIndex = null;
  const IntakeDefaultAction.mergeInto(int index)
      : kind = IntakeAction.mergeInto,
        targetIndex = index;
  final IntakeAction kind;
  final int? targetIndex;
}

class ProposalPlanner {
  ProposalPlanner._();

  /// Implements ADR-0001 merge rule γ: perishables always new Batch;
  /// non-perishables merge when name+unit+storage match.
  static IntakeDefaultAction computeIntakeDefaultAction({
    required IntakeCandidate candidate,
    required List<Ingredient> inventory,
  }) {
    if (FoodCategories.isPerishable(candidate.category)) {
      return const IntakeDefaultAction.newRow();
    }
    final candidateName = candidate.name.trim().toLowerCase();
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      if (row.name.trim().toLowerCase() != candidateName) continue;
      if (row.unit.trim() != candidate.unit.trim()) continue;
      if (row.storage != candidate.storage) continue;
      return IntakeDefaultAction.mergeInto(i);
    }
    return const IntakeDefaultAction.newRow();
  }
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/proposal_planner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/proposal_planner.dart test/proposal_planner_test.dart
git commit -m "feat(domain): ProposalPlanner.computeIntakeDefaultAction (rule γ)"
```

---

### Task 1.4: `InventoryNotifier.applyIntakeProposals`

**Files:**
- Modify: `lib/providers/inventory_provider.dart`
- Create: `test/inventory_apply_intake_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/inventory_apply_intake_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  List<Ingredient> seed = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(seed),
  ]);
}

IntakeProposal _newRow({
  String id = 'p1',
  String name = '苹果',
  String quantity = '5',
  String unit = '个',
  String category = FoodCategories.other,
  IconType storage = IconType.fridge,
  int? shelfLifeDays = 7,
}) =>
    IntakeProposal(
      id: id,
      name: name,
      quantity: quantity,
      unit: unit,
      category: category,
      storage: storage,
      shelfLifeDays: shelfLifeDays,
      action: IntakeAction.newRow,
    );

void main() {
  test('applyIntakeProposals: newRow creates an Ingredient', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyIntakeProposals([_newRow()]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1);
    expect(state.first.name, '苹果');
    expect(state.first.quantity, '5');
  });

  test('applyIntakeProposals: mergeInto adds quantity to existing row',
      () async {
    final existing = Ingredient(
      name: '米',
      quantity: '3',
      unit: 'kg',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.pantry,
    );
    final c = await _container(seed: [existing]);
    final notifier = c.read(inventoryProvider.notifier);

    final merge = IntakeProposal(
      id: 'p2',
      name: '米',
      quantity: '5',
      unit: 'kg',
      category: FoodCategories.other,
      storage: IconType.pantry,
      shelfLifeDays: null,
      action: IntakeAction.mergeInto,
      mergeTargetId: '0', // index 0 as string
    );

    await notifier.applyIntakeProposals([merge]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1,
        reason: 'merge must not create a new row');
    expect(state.first.quantity, '8',
        reason: 'quantity must sum 3 + 5 = 8');
  });

  test('applyIntakeProposals: skipped (selected=false) is ignored', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    final unselected = _newRow(id: 'p3').copyWith(selected: false);

    await notifier.applyIntakeProposals([unselected]);

    expect(c.read(inventoryProvider), isEmpty);
  });

  test('applyIntakeProposals: mixed list applies in given order', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyIntakeProposals([
      _newRow(id: 'a', name: '苹果'),
      _newRow(id: 'b', name: '香蕉'),
    ]);

    final state = c.read(inventoryProvider);
    expect(state.map((e) => e.name).toList(), ['苹果', '香蕉']);
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/inventory_apply_intake_test.dart`
Expected: FAIL — method undefined.

- [ ] **Step 3: Implement**

Add to `lib/providers/inventory_provider.dart` import block:

```dart
import '../models/proposal.dart';
```

Add inside class `InventoryNotifier`:

```dart
  /// Applies a list of IntakeProposals atomically: newRow proposals append,
  /// mergeInto proposals add quantity to the referenced row. Unselected
  /// proposals are ignored.
  Future<void> applyIntakeProposals(List<IntakeProposal> proposals) async {
    var current = [...state];
    for (final p in proposals) {
      if (!p.selected) continue;
      switch (p.action) {
        case IntakeAction.newRow:
          current = [...current, _ingredientFromProposal(p)];
        case IntakeAction.mergeInto:
          final index = int.tryParse(p.mergeTargetId ?? '');
          if (index == null || index < 0 || index >= current.length) {
            current = [...current, _ingredientFromProposal(p)];
            break;
          }
          final existing = current[index];
          final summed = _sumQuantity(existing.quantity, p.quantity);
          current = [...current]..[index] = _refreshIngredientFreshness(
                existing.copyWith(quantity: summed),
              );
      }
    }
    state = current;
    return queuePersistence(() => _save(current));
  }

  Ingredient _ingredientFromProposal(IntakeProposal p) {
    final shelf = p.shelfLifeDays;
    final addedAt = DateTime.now();
    final expiryDate =
        shelf == null ? null : addedAt.add(Duration(days: shelf));
    return _refreshIngredientFreshness(
      _normalizeIngredientCategory(
        Ingredient(
          name: p.name,
          quantity: p.quantity,
          unit: p.unit,
          imageUrl: '',
          freshnessPercent: 1.0,
          state: FreshnessState.fresh,
          category: p.category,
          storage: p.storage,
          expiryDate: expiryDate,
          addedAt: addedAt,
          shelfLifeDays: shelf,
        ),
      ),
    );
  }

  String _sumQuantity(String a, String b) {
    final na = double.tryParse(a) ?? 0;
    final nb = double.tryParse(b) ?? 0;
    final sum = na + nb;
    if (sum == sum.roundToDouble()) return sum.toInt().toString();
    return sum.toString();
  }
```

- [ ] **Step 4: Run test**

Run: `flutter test test/inventory_apply_intake_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/inventory_provider.dart test/inventory_apply_intake_test.dart
git commit -m "feat(inventory): applyIntakeProposals (newRow + merge sums quantity)"
```

---

### Task 1.5: `InventoryNotifier.applyDeductionProposals`

**Files:**
- Modify: `lib/providers/inventory_provider.dart`
- Create: `test/inventory_apply_deduction_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/inventory_apply_deduction_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ingredient _ing(String name, String qty, {String unit = '个'}) => Ingredient(
      name: name,
      quantity: qty,
      unit: unit,
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.fridge,
    );

Future<ProviderContainer> _container(List<Ingredient> seed) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(seed),
  ]);
}

void main() {
  test('deducts qty from chosen row', () async {
    final c = await _container([_ing('葱', '3')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 3 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1);
    expect(state.first.quantity, '2');
  });

  test('removes row when qty reaches 0', () async {
    final c = await _container([_ing('蒜', '1')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '蒜',
        requiredQty: '1瓣',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '蒜 1 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider), isEmpty);
  });

  test('skip action does not mutate inventory', () async {
    final c = await _container([_ing('葱', '3')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal.empty(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
      ),
    ]);

    expect(c.read(inventoryProvider).first.quantity, '3');
  });

  test('clamps negative result to 0 (and removes row)', () async {
    final c = await _container([_ing('盐', '0.5')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '盐',
        requiredQty: '1勺',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '盐 0.5'),
        ],
        chosenIndex: 0,
        deductAmount: '2',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider), isEmpty);
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/inventory_apply_deduction_test.dart`
Expected: FAIL — method undefined.

- [ ] **Step 3: Implement**

Add inside class `InventoryNotifier`:

```dart
  /// Applies a list of DeductionProposals atomically. Each Proposal references
  /// an inventory row by index; deducted quantities reaching 0 (or negative)
  /// remove the row.
  Future<void> applyDeductionProposals(List<DeductionProposal> proposals) async {
    final removalIndices = <int>{};
    var current = [...state];
    for (final p in proposals) {
      if (!p.selected) continue;
      if (p.action == DeductionAction.skip) continue;
      final i = p.chosenIndex;
      if (i < 0 || i >= current.length) continue;
      final existing = current[i];
      final remaining = _subtractQuantity(existing.quantity, p.deductAmount);
      if (remaining <= 0) {
        removalIndices.add(i);
      } else {
        final newQty = remaining == remaining.roundToDouble()
            ? remaining.toInt().toString()
            : remaining.toString();
        current[i] = _refreshIngredientFreshness(
          existing.copyWith(quantity: newQty),
        );
      }
    }
    if (removalIndices.isNotEmpty) {
      final sortedDesc = removalIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in sortedDesc) {
        current.removeAt(idx);
      }
    }
    state = List<Ingredient>.from(current);
    return queuePersistence(() => _save(state));
  }

  double _subtractQuantity(String existing, String deduct) {
    final ne = double.tryParse(existing) ?? 0;
    final nd = double.tryParse(deduct) ?? 0;
    return ne - nd;
  }
```

- [ ] **Step 4: Run test**

Run: `flutter test test/inventory_apply_deduction_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/inventory_provider.dart test/inventory_apply_deduction_test.dart
git commit -m "feat(inventory): applyDeductionProposals (remove on zero)"
```

---

## Phase 2: Shared Review Widgets

> All Phase 2 widgets live in `lib/widgets/review/`. They are stateless and pure rendering — state lives in the Phase 3 / 5 providers.

### Task 2.1: `ProvenanceBadge`

**Files:**
- Create: `lib/widgets/review/provenance_badge.dart`

- [ ] **Step 1: Implement**

```dart
// lib/widgets/review/provenance_badge.dart
import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';

class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({super.key, required this.origin, required this.userEdited});
  final FieldOrigin origin;
  final bool userEdited;

  @override
  Widget build(BuildContext context) {
    final (color, tooltip) = switch ((origin, userEdited)) {
      (_, true) => (AppColors.fkWarn, '手改'),
      (FieldOrigin.ai, _) => (AppColors.primary, 'AI 推断'),
      (FieldOrigin.system, _) => (AppColors.outline, '系统'),
      (FieldOrigin.user, _) => (AppColors.fkWarn, '手填'),
    };
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/review/provenance_badge.dart
git commit -m "feat(review): ProvenanceBadge dot (ai / system / user / 手改)"
```

---

### Task 2.2: `InlineNumberStepper`

**Files:**
- Create: `lib/widgets/review/inline_number_stepper.dart`
- Create: `test/inline_number_stepper_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/inline_number_stepper_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/review/inline_number_stepper.dart';

void main() {
  testWidgets('tap + and - calls onChanged with new value', (tester) async {
    var value = '5';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
            body: InlineNumberStepper(
              value: value,
              onChanged: (v) => setState(() => value = v),
              suffix: '天',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stepper_plus')));
    await tester.pump();
    expect(find.text('6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('clamps at min (default 0)', (tester) async {
    var value = '0';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
            body: InlineNumberStepper(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pump();
    expect(find.text('0'), findsOneWidget,
        reason: 'must not go below the configured min');
  });

  testWidgets('non-numeric value renders unmodified and disables steppers',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineNumberStepper(
            value: '一把',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('一把'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/inline_number_stepper_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/widgets/review/inline_number_stepper.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class InlineNumberStepper extends StatelessWidget {
  const InlineNumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.suffix,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int min;
  final int max;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(value);
    final canStep = parsed != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(
          key: const Key('stepper_minus'),
          icon: Icons.remove,
          onTap: canStep && parsed > min ? () => _bump(parsed, -1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            suffix == null ? value : '$value $suffix',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ),
        _btn(
          key: const Key('stepper_plus'),
          icon: Icons.add,
          onTap: canStep && parsed < max ? () => _bump(parsed, 1) : null,
        ),
      ],
    );
  }

  void _bump(double current, int delta) {
    final next = (current + delta).clamp(min.toDouble(), max.toDouble());
    final s = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toString();
    onChanged(s);
  }

  Widget _btn({required Key key, required IconData icon, VoidCallback? onTap}) {
    return InkResponse(
      key: key,
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceContainer,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? AppColors.outline : AppColors.onSurface,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/inline_number_stepper_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/review/inline_number_stepper.dart test/inline_number_stepper_test.dart
git commit -m "feat(review): InlineNumberStepper for qty + shelfLife"
```

---

### Task 2.3: `PickerSheet` — generic bottom-sheet picker

**Files:**
- Create: `lib/widgets/review/picker_sheet.dart`

- [ ] **Step 1: Implement**

```dart
// lib/widgets/review/picker_sheet.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.subtitle});
  final T value;
  final String label;
  final String? subtitle;
}

class PickerSheet<T> extends StatelessWidget {
  const PickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T? selected;

  /// Convenience: shows the sheet and returns the chosen value (or null on dismiss).
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<PickerOption<T>> options,
    required T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (_) => PickerSheet<T>(
        title: title,
        options: options,
        selected: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTypography.sectionTitle),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.hair),
                itemBuilder: (_, i) {
                  final opt = options[i];
                  final isSelected = opt.value == selected;
                  return ListTile(
                    title: Text(opt.label),
                    subtitle: opt.subtitle == null ? null : Text(opt.subtitle!),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(opt.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/review/picker_sheet.dart
git commit -m "feat(review): PickerSheet for unit / category / storage"
```

---

### Task 2.4: `ActionChip` — Intake action toggle

**Files:**
- Create: `lib/widgets/review/action_chip.dart`

- [ ] **Step 1: Implement**

```dart
// lib/widgets/review/action_chip.dart
import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';

/// Compact action chip displayed at the end of a Proposal row. Tapping cycles
/// through allowed actions (Intake: newRow ↔ mergeInto if a target exists;
/// Deduction: deduct ↔ skip). The chip's label and color reflect current state.
class ProposalActionChip extends StatelessWidget {
  const ProposalActionChip.intake({
    super.key,
    required this.intakeAction,
    required this.mergeTargetLabel,
    required this.onToggle,
  })  : deductionAction = null;

  const ProposalActionChip.deduction({
    super.key,
    required this.deductionAction,
    required this.onToggle,
  })  : intakeAction = null,
        mergeTargetLabel = null;

  final IntakeAction? intakeAction;
  final DeductionAction? deductionAction;
  final String? mergeTargetLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _styleFor();
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14, color: fg),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _styleFor() {
    if (intakeAction != null) {
      switch (intakeAction!) {
        case IntakeAction.newRow:
          return ('新建 Batch', AppColors.primarySoft, AppColors.primaryContainer);
        case IntakeAction.mergeInto:
          return (
            mergeTargetLabel == null ? '合并' : '合并 → $mergeTargetLabel',
            AppColors.fkWarnSoft,
            AppColors.onSecondaryContainer,
          );
      }
    }
    switch (deductionAction!) {
      case DeductionAction.deduct:
        return ('扣库存', AppColors.primarySoft, AppColors.primaryContainer);
      case DeductionAction.skip:
        return ('跳过', AppColors.surfaceContainer, AppColors.outline);
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/review/action_chip.dart
git commit -m "feat(review): ProposalActionChip (intake + deduction variants)"
```

---

### Task 2.5: `ReviewBottomBar` — sticky CTA

**Files:**
- Create: `lib/widgets/review/review_bottom_bar.dart`

- [ ] **Step 1: Implement**

```dart
// lib/widgets/review/review_bottom_bar.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ReviewBottomBar extends StatelessWidget {
  const ReviewBottomBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onToggleSelectAll,
    this.onCancel,
  });

  final int selectedCount;
  final int totalCount;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == totalCount && totalCount > 0;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onToggleSelectAll,
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              size: 18,
            ),
            label: Text(allSelected ? '取消全选' : '全选'),
          ),
          const Spacer(),
          if (onCancel != null) ...[
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton(
            onPressed: selectedCount == 0 ? null : onConfirm,
            child: Text('$confirmLabel ($selectedCount)'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/review/review_bottom_bar.dart
git commit -m "feat(review): ReviewBottomBar sticky CTA"
```

---

### Task 2.6: `ProposalRow` — Intake row assembler

**Files:**
- Create: `lib/widgets/review/proposal_row.dart`

> Each row composes provenance badge + checkbox + name (inline-editable) + action chip + qty stepper + shelfLife stepper + unit/category/storage chips that open PickerSheet.

- [ ] **Step 1: Implement Intake row**

```dart
// lib/widgets/review/proposal_row.dart
import 'package:flutter/material.dart';
import '../../data/food_categories.dart';
import '../../models/proposal.dart';
import '../../models/storage_area.dart';
import '../../theme/app_theme.dart';
import '../../utils/storage_labels.dart';
import 'action_chip.dart';
import 'inline_number_stepper.dart';
import 'picker_sheet.dart';
import 'provenance_badge.dart';

class IntakeProposalRow extends StatefulWidget {
  const IntakeProposalRow({
    super.key,
    required this.proposal,
    required this.onChanged,
    required this.onToggleSelected,
    required this.onToggleAction,
  });

  final IntakeProposal proposal;
  final ValueChanged<IntakeProposal> onChanged;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleAction;

  @override
  State<IntakeProposalRow> createState() => _IntakeProposalRowState();
}

class _IntakeProposalRowState extends State<IntakeProposalRow> {
  bool _editingName = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.proposal.name);
  }

  @override
  void didUpdateWidget(covariant IntakeProposalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editingName && oldWidget.proposal.name != widget.proposal.name) {
      _nameCtrl.text = widget.proposal.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.selected
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: p.selected ? AppColors.primary.withOpacity(0.3) : AppColors.hair,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onToggleSelected,
                child: Icon(
                  p.selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: p.selected ? AppColors.primary : AppColors.outline,
                ),
              ),
              const SizedBox(width: 8),
              ProvenanceBadge(origin: p.origin, userEdited: p.userEdited),
              const SizedBox(width: 8),
              Expanded(child: _name(p)),
              ProposalActionChip.intake(
                intakeAction: p.action,
                mergeTargetLabel: p.mergeTargetLabel,
                onToggle: widget.onToggleAction,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('数量', style: TextStyle(color: AppColors.outline, fontSize: 12)),
                const SizedBox(width: 6),
                InlineNumberStepper(
                  value: p.quantity,
                  onChanged: (v) => widget.onChanged(p.copyWith(quantity: v, userEdited: true)),
                ),
                const SizedBox(width: 4),
                _unitChip(p),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('保质期', style: TextStyle(color: AppColors.outline, fontSize: 12)),
                const SizedBox(width: 6),
                InlineNumberStepper(
                  value: (p.shelfLifeDays ?? 0).toString(),
                  onChanged: (v) => widget.onChanged(
                    p.copyWith(shelfLifeDays: int.tryParse(v) ?? 0, userEdited: true),
                  ),
                  suffix: '天',
                ),
              ]),
              _categoryChip(p),
              _storageChip(p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _name(IntakeProposal p) {
    if (!_editingName) {
      return GestureDetector(
        onTap: () => setState(() => _editingName = true),
        child: Text(
          p.name.isEmpty ? '(无名)' : p.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }
    return TextField(
      controller: _nameCtrl,
      autofocus: true,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      decoration: const InputDecoration(isDense: true, border: InputBorder.none),
      onSubmitted: (v) => _commitName(v),
      onTapOutside: (_) => _commitName(_nameCtrl.text),
    );
  }

  void _commitName(String v) {
    final trimmed = v.trim();
    if (trimmed != widget.proposal.name) {
      widget.onChanged(
          widget.proposal.copyWith(name: trimmed, userEdited: true));
    }
    setState(() => _editingName = false);
  }

  Widget _unitChip(IntakeProposal p) {
    return _pill(label: p.unit.isEmpty ? '单位' : p.unit, onTap: () async {
      final chosen = await PickerSheet.show<String>(
        context,
        title: '单位',
        options: const [
          PickerOption(value: '个', label: '个'),
          PickerOption(value: '只', label: '只'),
          PickerOption(value: '把', label: '把'),
          PickerOption(value: '盒', label: '盒'),
          PickerOption(value: '袋', label: '袋'),
          PickerOption(value: '瓶', label: '瓶'),
          PickerOption(value: '罐', label: '罐'),
          PickerOption(value: 'kg', label: 'kg'),
          PickerOption(value: 'g', label: 'g'),
          PickerOption(value: 'L', label: 'L'),
          PickerOption(value: 'ml', label: 'ml'),
          PickerOption(value: '份', label: '份'),
        ],
        selected: p.unit,
      );
      if (chosen != null) {
        widget.onChanged(p.copyWith(unit: chosen, userEdited: true));
      }
    });
  }

  Widget _categoryChip(IntakeProposal p) {
    return _pill(
      label: '分类:${p.category ?? '其他'}',
      onTap: () async {
        final chosen = await PickerSheet.show<String>(
          context,
          title: '分类',
          options: FoodCategories.values
              .map((c) => PickerOption(value: c, label: c))
              .toList(),
          selected: p.category,
        );
        if (chosen != null) {
          widget.onChanged(p.copyWith(category: chosen, userEdited: true));
        }
      },
    );
  }

  Widget _storageChip(IntakeProposal p) {
    return _pill(
      label: '存:${storageLabelFor(p.storage)}',
      onTap: () async {
        final chosen = await PickerSheet.show<IconType>(
          context,
          title: '存储位置',
          options: IconType.values
              .map((i) => PickerOption(value: i, label: storageLabelFor(i)))
              .toList(),
          selected: p.storage,
        );
        if (chosen != null) {
          widget.onChanged(p.copyWith(storage: chosen, userEdited: true));
        }
      },
    );
  }

  Widget _pill({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface)),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/review/proposal_row.dart
git commit -m "feat(review): IntakeProposalRow with hybrid edit UX"
```

---

## Phase 3: Intake — Paste Flow

### Task 3.1: `IntakeReviewState` + `IntakeReviewNotifier`

**Files:**
- Create: `lib/providers/intake_review_provider.dart`
- Create: `test/intake_review_provider_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/intake_review_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/intake_review_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
}

void main() {
  test('seed populates proposals and clears existing state', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.other,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      ),
    ]);
    expect(c.read(intakeReviewProvider).proposals.length, 1);
  });

  test('toggleSelected flips selected flag', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '苹果', quantity: '5', unit: '个',
        category: null, storage: IconType.fridge, shelfLifeDays: 7,
      ),
    ]);
    n.toggleSelected('p1');
    expect(c.read(intakeReviewProvider).proposals.first.selected, isFalse);
  });

  test('toggleAction cycles newRow ↔ mergeInto when target is present', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '米', quantity: '3', unit: 'kg',
        category: FoodCategories.other, storage: IconType.pantry, shelfLifeDays: null,
        action: IntakeAction.newRow,
        mergeTargetId: '0',
        mergeTargetLabel: '米 5kg',
      ),
    ]);
    n.toggleAction('p1');
    expect(c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.mergeInto);
    n.toggleAction('p1');
    expect(c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.newRow);
  });

  test('applyToInventory wires through InventoryNotifier and clears state',
      () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '苹果', quantity: '5', unit: '个',
        category: null, storage: IconType.fridge, shelfLifeDays: 7,
      ),
    ]);
    await n.applyToInventory(c.read(inventoryProvider.notifier));
    expect(c.read(intakeReviewProvider).proposals, isEmpty);
    expect(c.read(inventoryProvider).length, 1);
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/intake_review_provider_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/providers/intake_review_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'inventory_provider.dart';
import 'storage_service_provider.dart';

const intakeReviewDraftKey = 'intake_review_draft';

@immutable
class IntakeReviewState {
  const IntakeReviewState({this.proposals = const []});
  final List<IntakeProposal> proposals;

  IntakeReviewState copyWith({List<IntakeProposal>? proposals}) =>
      IntakeReviewState(proposals: proposals ?? this.proposals);

  int get selectedCount => proposals.where((p) => p.selected).length;
}

class IntakeReviewNotifier extends Notifier<IntakeReviewState> {
  @override
  IntakeReviewState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(intakeReviewDraftKey);
    if (raw == null) return const IntakeReviewState();
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return IntakeReviewState(
        proposals: list.map(_proposalFromJson).toList(),
      );
    } catch (_) {
      return const IntakeReviewState();
    }
  }

  void seed(List<IntakeProposal> proposals) {
    state = IntakeReviewState(proposals: proposals);
    _persistDraft();
  }

  void clear() {
    state = const IntakeReviewState();
    _persistDraft();
  }

  void toggleSelected(String id) {
    state = state.copyWith(
      proposals: state.proposals
          .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
          .toList(),
    );
    _persistDraft();
  }

  void toggleAction(String id) {
    state = state.copyWith(
      proposals: state.proposals.map((p) {
        if (p.id != id) return p;
        if (p.mergeTargetId == null) return p; // no merge target → can't toggle
        final next = p.action == IntakeAction.newRow
            ? IntakeAction.mergeInto
            : IntakeAction.newRow;
        return p.copyWith(action: next, userEdited: true);
      }).toList(),
    );
    _persistDraft();
  }

  void updateProposal(IntakeProposal updated) {
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.id == updated.id ? updated : p).toList(),
    );
    _persistDraft();
  }

  void toggleSelectAll() {
    final allSelected = state.proposals.every((p) => p.selected);
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.copyWith(selected: !allSelected)).toList(),
    );
    _persistDraft();
  }

  Future<void> applyToInventory(InventoryNotifier inventory) async {
    await inventory.applyIntakeProposals(state.proposals);
    clear();
  }

  Future<void> _persistDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (state.proposals.isEmpty) {
      await prefs.remove(intakeReviewDraftKey);
      return;
    }
    final encoded =
        jsonEncode(state.proposals.map(_proposalToJson).toList());
    await prefs.setString(intakeReviewDraftKey, encoded);
  }

  Map<String, dynamic> _proposalToJson(IntakeProposal p) => {
        'id': p.id,
        'name': p.name,
        'quantity': p.quantity,
        'unit': p.unit,
        'category': p.category,
        'storage': p.storage.name,
        'shelfLifeDays': p.shelfLifeDays,
        'action': p.action.name,
        'mergeTargetId': p.mergeTargetId,
        'mergeTargetLabel': p.mergeTargetLabel,
        'origin': p.origin.name,
        'userEdited': p.userEdited,
        'selected': p.selected,
      };

  IntakeProposal _proposalFromJson(Map<String, dynamic> j) => IntakeProposal(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        quantity: j['quantity'] as String? ?? '1',
        unit: j['unit'] as String? ?? '个',
        category: j['category'] as String?,
        storage: iconTypeFromName(j['storage'] as String?),
        shelfLifeDays: (j['shelfLifeDays'] as num?)?.toInt(),
        action: IntakeAction.values.byName(
            (j['action'] as String?) ?? IntakeAction.newRow.name),
        mergeTargetId: j['mergeTargetId'] as String?,
        mergeTargetLabel: j['mergeTargetLabel'] as String?,
        origin: FieldOrigin.values
            .byName((j['origin'] as String?) ?? FieldOrigin.ai.name),
        userEdited: j['userEdited'] as bool? ?? false,
        selected: j['selected'] as bool? ?? true,
      );
}

final intakeReviewProvider =
    NotifierProvider<IntakeReviewNotifier, IntakeReviewState>(
        IntakeReviewNotifier.new);
```

- [ ] **Step 4: Run test**

Run: `flutter test test/intake_review_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/intake_review_provider.dart test/intake_review_provider_test.dart
git commit -m "feat(review): IntakeReviewNotifier with draft persistence"
```

---

### Task 3.2: `IntakeReviewScreen`

**Files:**
- Create: `lib/screens/intake_review_screen.dart`

- [ ] **Step 1: Implement**

```dart
// lib/screens/intake_review_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/review/proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';

class IntakeReviewScreen extends ConsumerWidget {
  const IntakeReviewScreen({super.key, this.title = '审核入库'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(intakeReviewProvider);
    final n = ref.read(intakeReviewProvider.notifier);
    final inventoryN = ref.read(inventoryProvider.notifier);

    if (state.proposals.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '没有待审核的项目。\n回到上一屏粘贴清单或选择已购买项后再来。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.outline),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: state.proposals.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = state.proposals[i];
          return IntakeProposalRow(
            key: Key('intake_proposal_${p.id}'),
            proposal: p,
            onChanged: n.updateProposal,
            onToggleSelected: () => n.toggleSelected(p.id),
            onToggleAction: () => n.toggleAction(p.id),
          );
        },
      ),
      bottomNavigationBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.proposals.length,
        confirmLabel: '入库',
        onConfirm: () async {
          await n.applyToInventory(inventoryN);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已入库')),
          );
          Navigator.of(context).maybePop();
        },
        onToggleSelectAll: n.toggleSelectAll,
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
```

- [ ] **Step 2: Smoke render test**

```dart
// test/intake_review_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/intake_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/intake_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders one proposal row and shows confirm count',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: IntakeReviewScreen()),
      ),
    );
    // Empty state visible
    expect(find.textContaining('没有待审核'), findsOneWidget);

    // Seed and rebuild
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntakeReviewScreen)),
    );
    container.read(intakeReviewProvider.notifier).seed([
      IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.other,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('苹果'), findsOneWidget);
    expect(find.textContaining('入库 (1)'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test**

Run: `flutter test test/intake_review_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/intake_review_screen.dart test/intake_review_screen_test.dart
git commit -m "feat(review): IntakeReviewScreen (replaces ingredient_draft_review_screen)"
```

---

### Task 3.3: Add "粘贴清单" entry in Add tab

**Files:**
- Modify: `lib/screens/add_ingredient_screen.dart`
- Create: `test/add_paste_entry_test.dart`

The Add tab currently focuses on single-item entry. We add a primary entry button "粘贴清单" near the top that:
1. Opens a dialog with a multi-line `TextField` and an "解析" button.
2. On 解析: shows a loading spinner; calls `AiIngredientParser.fromText`.
3. Maps each `IngredientDraft` → `IntakeProposal` with `computeIntakeDefaultAction` against current inventory.
4. Seeds `intakeReviewProvider` and pushes `IntakeReviewScreen`.

- [ ] **Step 1: Write failing widget test**

```dart
// test/add_paste_entry_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('"粘贴清单" entry visible on AddIngredientScreen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paste_list_entry')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test**

Expected: FAIL.

- [ ] **Step 3: Implement entry button**

In `lib/screens/add_ingredient_screen.dart`, find the top of the scrollable body (likely near the existing "扫描" / 模式 switcher area). Insert a tappable card:

```dart
GestureDetector(
  key: const Key('paste_list_entry'),
  onTap: () => _openPasteDialog(context, ref),
  child: Container(
    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: const [
        Icon(Icons.content_paste_go, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '粘贴清单一次性录入',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Icon(Icons.chevron_right, color: AppColors.outline),
      ],
    ),
  ),
),
```

Add the dialog handler in the same file (free function or static method):

```dart
Future<void> _openPasteDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('粘贴清单'),
      content: TextField(
        controller: controller,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: '一行一项,例如:\n苹果 5 个\n牛奶 1 盒\n米 5kg',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('解析'),
        ),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;

  // Show loading + run AI parse
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final drafts = await AiIngredientParser.fromText(
      text,
      chatFn: ref.read(aiChatFnProvider),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loader

    final inventory = ref.read(inventoryProvider);
    final proposals = drafts.map((d) {
      final candidate = _IntakeCandidateFromDraft(d);
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final mergeIndex = defaultAction.targetIndex;
      return IntakeProposal(
        id: d.id,
        name: d.name.value,
        quantity: d.quantity.value,
        unit: d.unit.value,
        category: d.category.value,
        storage: d.storage.value ?? IconType.fridge,
        shelfLifeDays: d.shelfLifeDays.value,
        action: defaultAction.kind,
        mergeTargetId: mergeIndex?.toString(),
        mergeTargetLabel: mergeIndex == null
            ? null
            : '${inventory[mergeIndex].name} ${inventory[mergeIndex].quantity}${inventory[mergeIndex].unit}',
      );
    }).toList();

    ref.read(intakeReviewProvider.notifier).seed(proposals);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IntakeReviewScreen()),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loader
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('解析失败'),
        content: Text('$e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }
}

class _IntakeCandidateFromDraft implements IntakeCandidate {
  _IntakeCandidateFromDraft(this.d);
  final IngredientDraft d;
  @override String get name => d.name.value;
  @override String get unit => d.unit.value;
  @override IconType get storage => d.storage.value ?? IconType.fridge;
  @override String? get category => d.category.value;
}
```

Add imports at the top of `add_ingredient_screen.dart`:

```dart
import '../models/ingredient_draft.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../providers/ai_settings_provider.dart'; // if aiChatFnProvider lives here; otherwise wherever AiChatFn is provided
import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/ai_ingredient_parser.dart';
import '../services/proposal_planner.dart';
import 'intake_review_screen.dart';
```

> Subagent: if `aiChatFnProvider` does not exist with that name, find the actual provider exposing `AiChatFn` (likely in `ai_settings_provider.dart` or `providers/ai_client_provider.dart`) and use that.

- [ ] **Step 4: Run test**

Run: `flutter test test/add_paste_entry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/add_ingredient_screen.dart test/add_paste_entry_test.dart
git commit -m "feat(add): 粘贴清单 entry → AI parse → IntakeReviewScreen"
```

---

### Task 3.4: Migrate existing share-intent / image flows to IntakeReviewScreen

**Files:**
- Modify: `lib/app.dart` (or wherever share-intent navigates to ingredient_draft_review_screen)
- Modify: callers using `IngredientDraftReviewScreen`
- Delete: `lib/screens/ingredient_draft_review_screen.dart`

- [ ] **Step 1: Find all references to `IngredientDraftReviewScreen`**

Run: `grep -rn "IngredientDraftReviewScreen" lib/`

For each reference:
- Replace the navigation push target with `IntakeReviewScreen`.
- Before pushing, convert `aiDraftProvider.ingredientDrafts` → `List<IntakeProposal>` using the same mapping logic from Task 3.3 Step 3 (use `_IntakeCandidateFromDraft` and `ProposalPlanner.computeIntakeDefaultAction`).
- Call `ref.read(intakeReviewProvider.notifier).seed(proposals)` before pushing.

- [ ] **Step 2: Extract proposal conversion into a helper**

Create `lib/services/intake_proposal_factory.dart`:

```dart
// lib/services/intake_proposal_factory.dart
import '../models/ingredient.dart';
import '../models/ingredient_draft.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'proposal_planner.dart';

class IntakeProposalFactory {
  IntakeProposalFactory._();

  static List<IntakeProposal> fromDrafts(
    List<IngredientDraft> drafts,
    List<Ingredient> inventory,
  ) {
    return drafts.map((d) {
      final candidate = _Candidate(d);
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final i = defaultAction.targetIndex;
      return IntakeProposal(
        id: d.id,
        name: d.name.value,
        quantity: d.quantity.value,
        unit: d.unit.value,
        category: d.category.value,
        storage: d.storage.value ?? IconType.fridge,
        shelfLifeDays: d.shelfLifeDays.value,
        action: defaultAction.kind,
        mergeTargetId: i?.toString(),
        mergeTargetLabel: i == null
            ? null
            : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
      );
    }).toList();
  }
}

class _Candidate implements IntakeCandidate {
  _Candidate(this.d);
  final IngredientDraft d;
  @override String get name => d.name.value;
  @override String get unit => d.unit.value;
  @override IconType get storage => d.storage.value ?? IconType.fridge;
  @override String? get category => d.category.value;
}
```

- [ ] **Step 3: Refactor Task 3.3's inline conversion to use the factory**

In `add_ingredient_screen.dart`, replace the inline proposal construction with:

```dart
final proposals = IntakeProposalFactory.fromDrafts(drafts, inventory);
```

- [ ] **Step 4: Replace `IngredientDraftReviewScreen` callers**

For each call site, replace:

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => IngredientDraftReviewScreen(regenerate: regen),
));
```

with:

```dart
final inventory = ref.read(inventoryProvider);
final drafts = ref.read(aiDraftProvider).ingredientDrafts ?? const [];
ref.read(intakeReviewProvider.notifier).seed(
  IntakeProposalFactory.fromDrafts(drafts, inventory),
);
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => const IntakeReviewScreen(),
));
```

- [ ] **Step 5: Delete `lib/screens/ingredient_draft_review_screen.dart` and its test**

```bash
git rm lib/screens/ingredient_draft_review_screen.dart
# search for & delete its widget test if any
```

- [ ] **Step 6: `flutter analyze` + commit**

Run: `flutter analyze`
Expected: 0 errors (any callers that still reference the deleted screen will surface here).

```bash
git add -A
git commit -m "refactor(review): retire IngredientDraftReviewScreen in favor of IntakeReviewScreen"
```

---

## Phase 4: Intake — Shopping Completion Flow

### Task 4.1: ShoppingItem → IntakeProposal factory

**Files:**
- Modify: `lib/services/intake_proposal_factory.dart`
- Create: `test/intake_proposal_factory_shopping_test.dart`

`ShoppingItem` has `name / detail / category / isChecked`. `detail` is a free-form string like "1 个". We do a best-effort parse: prefix number = quantity, rest = unit (default "份" if blank). `shelfLifeDays` is null (user will set in Review).

- [ ] **Step 1: Write failing tests**

```dart
// test/intake_proposal_factory_shopping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/intake_proposal_factory.dart';

void main() {
  group('IntakeProposalFactory.fromShoppingItems', () {
    test('parses "5 个" detail into quantity=5 unit=个', () {
      final items = [
        ShoppingItem(
          id: 'si1', name: '苹果', detail: '5 个',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals, hasLength(1));
      expect(proposals.first.quantity, '5');
      expect(proposals.first.unit, '个');
    });

    test('handles missing detail gracefully', () {
      final items = [
        ShoppingItem(
          id: 'si2', name: '葱', detail: '',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals.first.quantity, '1');
      expect(proposals.first.unit, '份');
    });

    test('origin=system and shelfLifeDays=null when no inventory match', () {
      final items = [
        ShoppingItem(
          id: 'si3', name: '盐', detail: '1 袋',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals.first.origin, FieldOrigin.system);
      expect(proposals.first.shelfLifeDays, isNull);
    });

    test('merge default action when inventory has matching non-perishable row',
        () {
      final inventory = [
        Ingredient(
          name: '米', quantity: '3', unit: 'kg', imageUrl: '',
          freshnessPercent: 1, state: FreshnessState.fresh,
          category: FoodCategories.other, storage: IconType.pantry,
        ),
      ];
      final items = [
        ShoppingItem(
          id: 'si4', name: '米', detail: '5 kg',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals = IntakeProposalFactory.fromShoppingItems(items, inventory);
      expect(proposals.first.action, IntakeAction.mergeInto);
    });
  });
}
```

- [ ] **Step 2: Run test**

Expected: FAIL.

- [ ] **Step 3: Implement**

Append to `lib/services/intake_proposal_factory.dart`:

```dart
class IntakeProposalFactory {
  // ... existing fromDrafts ...

  static List<IntakeProposal> fromShoppingItems(
    List<ShoppingItem> items,
    List<Ingredient> inventory,
  ) {
    return items.map((item) {
      final (qty, unit) = _parseDetail(item.detail);
      final candidate = _ShoppingCandidate(
        name: item.name,
        unit: unit,
        storage: IconType.fridge, // default; user adjusts in Review
        category: item.category,
      );
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final i = defaultAction.targetIndex;
      return IntakeProposal(
        id: 'ix_${item.id}',
        name: item.name,
        quantity: qty,
        unit: unit,
        category: item.category,
        storage: IconType.fridge,
        shelfLifeDays: null,
        action: defaultAction.kind,
        mergeTargetId: i?.toString(),
        mergeTargetLabel: i == null
            ? null
            : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
        origin: FieldOrigin.system,
      );
    }).toList();
  }

  static (String qty, String unit) _parseDetail(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return ('1', '份');
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(trimmed);
    if (m == null) return ('1', trimmed);
    return (m.group(1) ?? '1', (m.group(2) ?? '').trim().isEmpty
        ? '份'
        : (m.group(2) ?? '').trim());
  }
}

class _ShoppingCandidate implements IntakeCandidate {
  _ShoppingCandidate({
    required this.name,
    required this.unit,
    required this.storage,
    required this.category,
  });
  @override final String name;
  @override final String unit;
  @override final IconType storage;
  @override final String? category;
}
```

You also need to add an import for `ShoppingItem`:

```dart
import '../models/shopping_item.dart';
```

- [ ] **Step 4: Run test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/intake_proposal_factory.dart test/intake_proposal_factory_shopping_test.dart
git commit -m "feat(review): IntakeProposalFactory.fromShoppingItems"
```

---

### Task 4.2: Shopping list — sticky CTA "已购买的 N 项一键入库"

**Files:**
- Modify: `lib/screens/shopping_list_screen.dart`
- Create: `test/shopping_to_intake_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/shopping_to_intake_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/shopping_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sticky CTA appears when any item is checked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final seed = [
      ShoppingItem(
        id: 'si1', name: '苹果', detail: '5 个',
        category: FoodCategories.other, isChecked: true,
      ),
      ShoppingItem(
        id: 'si2', name: '盐', detail: '1 袋',
        category: FoodCategories.other, isChecked: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          shoppingSeedProvider.overrideWithValue(seed),
        ],
        child: const MaterialApp(home: ShoppingListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shopping_to_intake_cta')), findsOneWidget);
    expect(find.textContaining('1 项'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test**

Expected: FAIL.

- [ ] **Step 3: Implement sticky CTA**

In `lib/screens/shopping_list_screen.dart`, watch `checkedCountProvider` and the full list. At the bottom of the `Scaffold` (or `body` Stack), add a sticky CTA that is visible only when `checkedCount > 0`:

```dart
final checked = ref.watch(checkedCountProvider);
// inside Stack or as bottomSheet:
if (checked > 0)
  SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: FilledButton(
      key: const Key('shopping_to_intake_cta'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
      onPressed: () => _openIntakeReviewForChecked(context, ref),
      child: Text('已购买的 $checked 项一键入库'),
    ),
  ),
```

Implement handler at the end of the file:

```dart
Future<void> _openIntakeReviewForChecked(
  BuildContext context,
  WidgetRef ref,
) async {
  final all = ref.read(shoppingProvider);
  final checked = all.where((i) => i.isChecked).toList();
  if (checked.isEmpty) return;

  final inventory = ref.read(inventoryProvider);
  final proposals =
      IntakeProposalFactory.fromShoppingItems(checked, inventory);
  ref.read(intakeReviewProvider.notifier).seed(proposals);

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          const IntakeReviewScreen(title: '已购买项入库'),
    ),
  );

  // After review (whether confirmed or cancelled), remove only items whose
  // proposals were actually applied. We approximate "applied" as: the
  // intakeReviewProvider has cleared (clear() runs only after apply).
  final remaining = ref.read(intakeReviewProvider).proposals;
  if (remaining.isEmpty) {
    final shopping = ref.read(shoppingProvider.notifier);
    for (final item in checked) {
      await shopping.remove(item.id);
    }
  }
}
```

Imports to add at top of file:

```dart
import '../providers/inventory_provider.dart';
import '../providers/intake_review_provider.dart';
import '../services/intake_proposal_factory.dart';
import 'intake_review_screen.dart';
```

- [ ] **Step 4: Run test**

Expected: PASS.

- [ ] **Step 5: Manual smoke**

```bash
flutter run -d ios
```

- Open Shopping tab.
- Check 2 items → verify "已购买的 2 项一键入库" CTA appears.
- Tap CTA → IntakeReviewScreen with the 2 items as proposals.
- Confirm → SnackBar "已入库". Return to Shopping; the 2 items should be gone from the list.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/shopping_list_screen.dart test/shopping_to_intake_test.dart
git commit -m "feat(shopping): 已购买项一键入库 → IntakeReviewScreen"
```

---

## Phase 5: Deduction — Cook Flow

### Task 5.1: `DeductionReviewState` + `DeductionReviewNotifier`

**Files:**
- Create: `lib/providers/deduction_review_provider.dart`
- Create: `test/deduction_review_provider_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/deduction_review_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
}

void main() {
  test('seed + toggleSelected + toggleAction', () async {
    final c = await _container();
    final n = c.read(deductionReviewProvider.notifier);
    n.seed([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 1 把'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
      ),
    ]);
    expect(c.read(deductionReviewProvider).proposals, hasLength(1));

    n.toggleSelected('d1');
    expect(c.read(deductionReviewProvider).proposals.first.selected, isFalse);

    n.toggleAction('d1');
    expect(c.read(deductionReviewProvider).proposals.first.action,
        DeductionAction.skip);
    n.toggleAction('d1');
    expect(c.read(deductionReviewProvider).proposals.first.action,
        DeductionAction.deduct);
  });
}
```

- [ ] **Step 2: Run test**

Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/providers/deduction_review_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proposal.dart';
import 'inventory_provider.dart';

@immutable
class DeductionReviewState {
  const DeductionReviewState({this.proposals = const []});
  final List<DeductionProposal> proposals;
  int get selectedCount =>
      proposals.where((p) => p.selected && p.action == DeductionAction.deduct).length;
}

class DeductionReviewNotifier extends Notifier<DeductionReviewState> {
  @override
  DeductionReviewState build() => const DeductionReviewState();

  void seed(List<DeductionProposal> proposals) =>
      state = DeductionReviewState(proposals: proposals);

  void clear() => state = const DeductionReviewState();

  void toggleSelected(String id) {
    state = DeductionReviewState(
      proposals: state.proposals
          .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
          .toList(),
    );
  }

  void toggleAction(String id) {
    state = DeductionReviewState(
      proposals: state.proposals.map((p) {
        if (p.id != id) return p;
        final next = p.action == DeductionAction.deduct
            ? DeductionAction.skip
            : DeductionAction.deduct;
        return p.copyWith(action: next);
      }).toList(),
    );
  }

  void chooseCandidate(String id, int candidateRowIndex) {
    state = DeductionReviewState(
      proposals: state.proposals
          .map((p) => p.id == id ? p.copyWith(chosenIndex: candidateRowIndex) : p)
          .toList(),
    );
  }

  void updateDeductAmount(String id, String amount) {
    state = DeductionReviewState(
      proposals: state.proposals
          .map((p) => p.id == id ? p.copyWith(deductAmount: amount) : p)
          .toList(),
    );
  }

  Future<void> applyToInventory(InventoryNotifier inventory) async {
    await inventory.applyDeductionProposals(state.proposals);
    clear();
  }
}

final deductionReviewProvider =
    NotifierProvider<DeductionReviewNotifier, DeductionReviewState>(
        DeductionReviewNotifier.new);
```

- [ ] **Step 4: Run test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/deduction_review_provider.dart test/deduction_review_provider_test.dart
git commit -m "feat(review): DeductionReviewNotifier"
```

---

### Task 5.2: Fuzzy match — recipe ingredient → inventory rows

**Files:**
- Modify: `lib/services/proposal_planner.dart`
- Create: `test/proposal_planner_deduction_match_test.dart`

The fuzzy match: case-insensitive substring containment in either direction (mirrors current `recipe_detail_screen.dart` line 420 logic). Returns matched inventory indices sorted by earliest expiry first (so users by default deduct from the closest-to-expire batch).

- [ ] **Step 1: Write failing tests**

```dart
// test/proposal_planner_deduction_match_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/proposal_planner.dart';

Ingredient _ing({
  required String name, String qty = '1', DateTime? expiry,
}) =>
    Ingredient(
      name: name, quantity: qty, unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      category: FoodCategories.other, storage: IconType.fridge,
      expiryDate: expiry, addedAt: DateTime(2026, 5, 1),
    );

void main() {
  test('returns matching inventory rows sorted by earliest expiry', () {
    final inventory = [
      _ing(name: '葱', qty: '1', expiry: DateTime(2026, 5, 30)), // index 0
      _ing(name: '香葱', qty: '1', expiry: DateTime(2026, 5, 20)), // index 1
      _ing(name: '盐', qty: '1'),                                 // index 2 (no match)
    ];
    final matches = ProposalPlanner.fuzzyMatchInventoryRows('葱', inventory);
    expect(matches.map((m) => m.inventoryRowIndex).toList(), [1, 0]);
  });

  test('no match → empty list', () {
    final inventory = [_ing(name: '盐', qty: '1')];
    expect(ProposalPlanner.fuzzyMatchInventoryRows('葱', inventory), isEmpty);
  });

  test('substring containment in either direction', () {
    final inventory = [_ing(name: '猪肉末', qty: '1')];
    expect(ProposalPlanner.fuzzyMatchInventoryRows('猪肉', inventory),
        isNotEmpty);
    expect(ProposalPlanner.fuzzyMatchInventoryRows('肉', inventory),
        isNotEmpty);
  });
}
```

- [ ] **Step 2: Run test**

Expected: FAIL.

- [ ] **Step 3: Implement**

Append to `lib/services/proposal_planner.dart`:

```dart
import '../models/proposal.dart' show DeductionCandidate;
// (add at top if not present)

// Inside class ProposalPlanner:
  static List<DeductionCandidate> fuzzyMatchInventoryRows(
    String recipeIngredientName,
    List<Ingredient> inventory,
  ) {
    final query = recipeIngredientName.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final matches = <(int, Ingredient)>[];
    for (var i = 0; i < inventory.length; i++) {
      final n = inventory[i].name.trim().toLowerCase();
      if (n == query || n.contains(query) || query.contains(n)) {
        matches.add((i, inventory[i]));
      }
    }
    matches.sort((a, b) {
      final ea = a.$2.expiryDate;
      final eb = b.$2.expiryDate;
      if (ea == null && eb == null) return 0;
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });
    return matches
        .map((m) => DeductionCandidate(
              inventoryRowIndex: m.$1,
              displayLabel:
                  '${m.$2.name} ${m.$2.quantity}${m.$2.unit}${m.$2.expiryLabel == null ? '' : ' · ${m.$2.expiryLabel}'}',
            ))
        .toList();
  }
```

- [ ] **Step 4: Run test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/proposal_planner.dart test/proposal_planner_deduction_match_test.dart
git commit -m "feat(review): fuzzy match recipe ingredients to inventory rows"
```

---

### Task 5.3: `DeductionReviewScreen`

**Files:**
- Create: `lib/widgets/review/deduction_proposal_row.dart`
- Create: `lib/screens/deduction_review_screen.dart`

- [ ] **Step 1: Implement DeductionProposalRow**

```dart
// lib/widgets/review/deduction_proposal_row.dart
import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';
import 'action_chip.dart';
import 'inline_number_stepper.dart';
import 'picker_sheet.dart';

class DeductionProposalRow extends StatelessWidget {
  const DeductionProposalRow({
    super.key,
    required this.proposal,
    required this.onToggleSelected,
    required this.onToggleAction,
    required this.onChooseCandidate,
    required this.onChangeAmount,
  });

  final DeductionProposal proposal;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleAction;
  final ValueChanged<int> onChooseCandidate;
  final ValueChanged<String> onChangeAmount;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final chosen = p.candidates
        .firstWhere(
          (c) => c.inventoryRowIndex == p.chosenIndex,
          orElse: () => p.candidates.isEmpty
              ? const DeductionCandidate(inventoryRowIndex: -1, displayLabel: '')
              : p.candidates.first,
        );
    final isSkip = p.action == DeductionAction.skip;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSkip ? AppColors.surfaceContainerLow : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: onToggleSelected,
              child: Icon(
                p.selected ? Icons.check_box : Icons.check_box_outline_blank,
                color: p.selected ? AppColors.primary : AppColors.outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.recipeIngredientName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (p.requiredQty.isNotEmpty)
                    Text('菜谱需要 ${p.requiredQty}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.outline)),
                ],
              ),
            ),
            ProposalActionChip.deduction(
              deductionAction: p.action,
              onToggle: onToggleAction,
            ),
          ]),
          if (!isSkip && p.candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await PickerSheet.show<int>(
                  context,
                  title: '扣减来源批次',
                  options: p.candidates
                      .map((c) => PickerOption(
                          value: c.inventoryRowIndex, label: c.displayLabel))
                      .toList(),
                  selected: p.chosenIndex,
                );
                if (picked != null) onChooseCandidate(picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 16, color: AppColors.onSurface),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        chosen.inventoryRowIndex == -1
                            ? '无可用批次'
                            : chosen.displayLabel,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.unfold_more,
                        size: 16, color: AppColors.outline),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('扣减', style: TextStyle(color: AppColors.outline, fontSize: 12)),
              const SizedBox(width: 6),
              InlineNumberStepper(
                value: p.deductAmount,
                onChanged: onChangeAmount,
              ),
            ]),
          ] else if (p.candidates.isEmpty) ...[
            const SizedBox(height: 4),
            const Text('库存中没有匹配项,这条将被跳过。',
                style: TextStyle(color: AppColors.outline, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Implement DeductionReviewScreen**

```dart
// lib/screens/deduction_review_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/deduction_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../widgets/review/deduction_proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';

class DeductionReviewScreen extends ConsumerWidget {
  const DeductionReviewScreen({super.key, this.title = '审核扣库存'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deductionReviewProvider);
    final n = ref.read(deductionReviewProvider.notifier);
    final inv = ref.read(inventoryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: state.proposals.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这道菜的食材没有可扣减的库存项。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: state.proposals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = state.proposals[i];
                return DeductionProposalRow(
                  key: Key('deduction_proposal_${p.id}'),
                  proposal: p,
                  onToggleSelected: () => n.toggleSelected(p.id),
                  onToggleAction: () => n.toggleAction(p.id),
                  onChooseCandidate: (idx) => n.chooseCandidate(p.id, idx),
                  onChangeAmount: (v) => n.updateDeductAmount(p.id, v),
                );
              },
            ),
      bottomNavigationBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.proposals.length,
        confirmLabel: '确认扣减',
        onConfirm: () async {
          await n.applyToInventory(inv);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已扣减库存')),
          );
          Navigator.of(context).maybePop();
        },
        onToggleSelectAll: () {
          // No-op for deduction; selection per row only.
        },
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
```

- [ ] **Step 3: Smoke widget test**

```dart
// test/deduction_review_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/deduction_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders proposals and confirm button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: DeductionReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DeductionReviewScreen)));
    container.read(deductionReviewProvider.notifier).seed([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 1 把'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('葱'), findsOneWidget);
    expect(find.textContaining('确认扣减 (1)'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run tests + commit**

Run: `flutter test test/deduction_review_screen_test.dart`
Expected: PASS.

```bash
git add lib/widgets/review/deduction_proposal_row.dart lib/screens/deduction_review_screen.dart test/deduction_review_screen_test.dart
git commit -m "feat(review): DeductionReviewScreen with per-row candidate picker"
```

---

### Task 5.4: "我做了" button on recipe_detail + seed flow

**Files:**
- Modify: `lib/screens/recipe_detail_screen.dart`
- Create: `lib/services/deduction_proposal_factory.dart`
- Create: `test/recipe_completion_flow_test.dart`

- [ ] **Step 1: Implement factory**

```dart
// lib/services/deduction_proposal_factory.dart
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/recipe.dart';
import 'proposal_planner.dart';

class DeductionProposalFactory {
  DeductionProposalFactory._();

  static List<DeductionProposal> forRecipe(
    Recipe recipe,
    List<Ingredient> inventory,
  ) {
    final list = <DeductionProposal>[];
    for (var i = 0; i < recipe.ingredients.length; i++) {
      final ri = recipe.ingredients[i];
      final candidates =
          ProposalPlanner.fuzzyMatchInventoryRows(ri.name, inventory);
      if (candidates.isEmpty) {
        list.add(DeductionProposal.empty(
          id: 'd_${recipe.id}_$i',
          recipeIngredientName: ri.name,
          requiredQty: ri.amount,
        ));
      } else {
        list.add(DeductionProposal(
          id: 'd_${recipe.id}_$i',
          recipeIngredientName: ri.name,
          requiredQty: ri.amount,
          candidates: candidates,
          chosenIndex: candidates.first.inventoryRowIndex,
          deductAmount: ri.quantity.trim().isEmpty ? '1' : ri.quantity,
        ));
      }
    }
    return list;
  }
}
```

- [ ] **Step 2: Add "我做了" button to recipe_detail_screen**

In `lib/screens/recipe_detail_screen.dart`, near the bottom action buttons (`加入清单 / 标记已用完`), add:

```dart
FilledButton.icon(
  key: const Key('recipe_cooked_action'),
  icon: const Icon(Icons.restaurant),
  label: const Text('我做了'),
  onPressed: () async {
    final inv = ref.read(inventoryProvider);
    final proposals =
        DeductionProposalFactory.forRecipe(widget.recipe, inv);
    ref.read(deductionReviewProvider.notifier).seed(proposals);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeductionReviewScreen()),
    );
  },
),
```

Imports to add:

```dart
import '../providers/deduction_review_provider.dart';
import '../services/deduction_proposal_factory.dart';
import 'deduction_review_screen.dart';
```

- [ ] **Step 3: Write integration widget test**

```dart
// test/recipe_completion_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tapping 我做了 navigates to DeductionReviewScreen and applies',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final inventory = [
      Ingredient(
        name: '葱', quantity: '3', unit: '把', imageUrl: '',
        freshnessPercent: 1, state: FreshnessState.fresh,
        category: FoodCategories.freshProduce, storage: IconType.fridge,
      ),
    ];
    final recipe = Recipe(
      id: 'r1', name: '葱花蛋', category: '中餐',
      difficulty: 1, cookingMinutes: 10, description: '',
      ingredients: [RecipeIngredient(name: '葱', quantity: '1', unit: '把')],
      steps: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          inventorySeedProvider.overrideWithValue(inventory),
        ],
        child: MaterialApp(home: RecipeDetailScreen(recipe: recipe)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recipe_cooked_action')));
    await tester.pumpAndSettle();

    expect(find.text('葱'), findsWidgets);
    expect(find.textContaining('确认扣减'), findsOneWidget);

    await tester.tap(find.textContaining('确认扣减'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeDetailScreen)));
    expect(container.read(inventoryProvider).first.quantity, '2',
        reason: '3 - 1 = 2');
  });
}
```

- [ ] **Step 4: Run test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/deduction_proposal_factory.dart lib/screens/recipe_detail_screen.dart test/recipe_completion_flow_test.dart
git commit -m "feat(recipe): 我做了 button → DeductionReviewScreen"
```

---

## Phase 6: Polish

### Task 6.1: Inventory list — long-press multi-select "合并这两批"

**Files:**
- Modify: `lib/screens/inventory_screen.dart`
- Modify: `lib/providers/inventory_provider.dart`
- Create: `test/inventory_merge_batches_test.dart`

- [ ] **Step 1: Add `mergeBatch` to InventoryNotifier**

In `inventory_provider.dart`:

```dart
  /// Merges two inventory rows (`sourceIndex` into `targetIndex`):
  /// quantities sum, expiry takes the earlier of the two (so urgency signal
  /// is preserved), source row is removed.
  Future<void> mergeBatch(int sourceIndex, int targetIndex) async {
    if (sourceIndex == targetIndex) return;
    if (sourceIndex < 0 || sourceIndex >= state.length) return;
    if (targetIndex < 0 || targetIndex >= state.length) return;
    final source = state[sourceIndex];
    final target = state[targetIndex];
    if (source.unit.trim() != target.unit.trim()) return;
    if (source.storage != target.storage) return;
    final summed = _sumQuantity(source.quantity, target.quantity);
    final earlierExpiry = _earlierExpiry(source.expiryDate, target.expiryDate);
    final mergedTarget = _refreshIngredientFreshness(
      target.copyWith(quantity: summed, expiryDate: earlierExpiry),
    );
    final updated = [...state]..[targetIndex] = mergedTarget;
    updated.removeAt(sourceIndex);
    state = updated;
    return queuePersistence(() => _save(updated));
  }

  DateTime? _earlierExpiry(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
```

- [ ] **Step 2: Write tests**

```dart
// test/inventory_merge_batches_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ingredient _ing({
  required String qty, DateTime? expiry,
}) =>
    Ingredient(
      name: '牛奶', quantity: qty, unit: '盒', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      category: FoodCategories.dairyAndEggs, storage: IconType.fridge,
      expiryDate: expiry,
    );

void main() {
  test('mergeBatch sums qty and keeps earlier expiry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue([
        _ing(qty: '1', expiry: DateTime(2026, 5, 30)),  // 0: new
        _ing(qty: '1', expiry: DateTime(2026, 5, 20)),  // 1: old
      ]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 1);
    final state = c.read(inventoryProvider);
    expect(state.length, 1);
    expect(state.first.quantity, '2');
    expect(state.first.expiryDate, DateTime(2026, 5, 20),
        reason: 'must take earlier of the two expiries');
  });
}
```

- [ ] **Step 3: Run test**

Expected: PASS.

- [ ] **Step 4: Wire UI**

In `inventory_screen.dart`, add long-press selection state (Set<int>) and a contextual app bar. When ≥ 2 rows of the same name/unit/storage are selected, show a "合并 N 批" button that calls `mergeBatch` pair-wise (n-1 calls, source→target reduced).

> Skeleton (subagent fills layout):
>
> ```dart
> Set<int> _selected = {};
> bool _selectionMode = false;
>
> void _onLongPress(int index) {
>   setState(() {
>     _selectionMode = true;
>     _selected.add(index);
>   });
> }
>
> Future<void> _mergeSelected() async {
>   final indices = _selected.toList()..sort((a, b) => b.compareTo(a));
>   if (indices.length < 2) return;
>   final notifier = ref.read(inventoryProvider.notifier);
>   final target = indices.last;
>   for (final src in indices.where((i) => i != target)) {
>     await notifier.mergeBatch(src, target);
>   }
>   setState(() {
>     _selectionMode = false;
>     _selected.clear();
>   });
> }
> ```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/inventory_screen.dart lib/providers/inventory_provider.dart test/inventory_merge_batches_test.dart
git commit -m "feat(inventory): long-press multi-select → 合并 N 批"
```

---

### Task 6.2: Integration smoke + final analyze

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS (all phases).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

- [ ] **Step 3: Manual smoke checklist on device**

```bash
flutter run -d ios
```

Verify each flow:
- **Paste flow**: Add tab → 粘贴清单 → input "苹果 5个\n牛奶 1盒\n米 5kg" → 解析 → IntakeReviewScreen shows 3 rows with mixed action chips (perishable 牛奶 = newRow, 米 should propose merge if inventory has matching row) → tweak one shelfLife inline → 入库 → SnackBar.
- **Shopping flow**: Shopping tab → check 2 items → CTA "已购买的 2 项一键入库" appears → tap → IntakeReviewScreen → 入库 → return to shopping; checked items are gone.
- **Cook flow**: Recipe detail → 我做了 → DeductionReviewScreen with each recipe ingredient as a row (matched / "无可用批次" for unmatched) → 取消 one row's action chip → 确认扣减 → snack; inventory's matched item quantity dropped.
- **Inventory merge**: Inventory tab → long-press a row → tap a second matching row → 合并按钮 → row count drops, expiry takes earlier batch.
- **Back-button persistence**: Paste a list, partially edit, hit Android back → re-open IntakeReviewScreen → edits preserved.

- [ ] **Step 4: Final commit + push**

```bash
git push -u origin HEAD
```

---

## Self-Review

**Spec coverage (against the grilling conclusions):**
- ✅ Three triggers funnel through unified Review mental model (Phases 3 / 4 / 5)
- ✅ ADR-0001 merge rule γ (`isPerishable`, `computeIntakeDefaultAction`)
- ✅ 2 Review screens + shared widgets in `lib/widgets/review/` (Phases 2-5)
- ✅ Hybrid edit UX: inline steppers for qty / shelfLife, sheet for unit / category / storage, inline TextField for name (Task 2.6)
- ✅ Draft persistence so back-button doesn't lose work (Task 3.1)
- ✅ Failure: AI 0 / parse error → empty state in screen; loader-dialog dismissal + error dialog in Task 3.3
- ✅ Manual batch merge affordance (Task 6.1)

**Placeholder scan:**
- One soft-spot in Task 3.3: `aiChatFnProvider` may not exist with that exact name — fix is annotated inline (subagent must locate the real provider). This is the only unresolved name; the rest of the types and methods are defined within this plan or already exist in the codebase.

**Type consistency:**
- `IntakeProposal` / `DeductionProposal` / `IntakeAction` / `DeductionAction` / `FieldOrigin` defined in Task 1.2 are used identically across Tasks 1.3-6.1.
- `IntakeProposalFactory.fromDrafts` (Task 3.4) / `fromShoppingItems` (Task 4.1) / `DeductionProposalFactory.forRecipe` (Task 5.4) all match the signature shapes expected by the screens and notifiers.
- `applyIntakeProposals` / `applyDeductionProposals` / `mergeBatch` on `InventoryNotifier` are consistent across their tests and call sites.

**Risk register:**
- **Quantity stays `String`**: tests pin "non-numeric quantity strings (e.g. 一把) render unmodified and disable steppers" (Task 2.2). If the user's data has many non-numeric quantities, the stepper is just decoration — that's accepted scope.
- **`mergeTargetId` is the inventory index at compute-time**: if inventory mutates between proposal computation and apply (e.g. concurrent edits), the merge may target the wrong row. Mitigation: tests bound this with `applyIntakeProposals` happening in a single state read; for self-use this race is acceptable.
- **AI provider name unknown**: Task 3.3 Step 3 annotates the lookup. Subagent must `grep -rn "AiChatFn\|ai_client" lib/` and pick the existing wiring.
- **Test against device locale**: Snackbar / dialog text contains zh-CN strings; tests assert via substring or key, not full-text equality, so they should pass under any locale binding.

---

## Out of plan — pickup for Stage 1.5

Items deferred per grilling:
- Add tab "拍照" / "拍小票" entries (Tasks 3.3 candidate options b / c) — observe Stage 1 paste flow dogfood first.
- Cross-unit conversion in Deduction (e.g. recipe asks `50g` but inventory has `1把`) — currently flagged visually, user-decided.
- Pull-to-refresh / autorefresh `inventoryProvider` after import (Stage 0).
- Replace SnackBar with FK `fkToast` once that utility is confirmed across the app.

These are tracked here, not as separate plans, to keep the Stage 1 docket clean.
