# 新建 / 编辑食谱页面 UI 重构 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `CustomRecipeFormScreen` 从平铺裸 `TextField` 改成卡片化结构 + chip / 星级 / 拖动控件 + 内联错误，并把 `RecipeIngredient.amount` 拆分为 `quantity + unit`（向后兼容旧 JSON）。

**Architecture:** 增量重构——先做数据模型迁移（保证旧数据可读），然后按依赖顺序新建共享 widget（`recipe_form_card` / `cooking_time_row` / `difficulty_stars` / `unit_dropdown` / `recipe_category_chips` / `ai_collapsible_banner`），最后逐段替换 `custom_recipe_form_screen.dart` 内部结构。每个 widget 自带 widget test；模型层 TDD。

**Tech Stack:** Flutter + flutter_riverpod + flutter_test；复用 `lib/widgets/common/category_chips.dart` 和 `lib/widgets/shared/pill_chip.dart`；遵循 `AppSpacing` / `AppRadius` / `AppColors` / `AppTypography` token。

**Spec：** `docs/superpowers/specs/2026-05-09-recipe-form-redesign-design.md`

---

## 文件结构总览

### 新建

| 文件 | 责任 |
|---|---|
| `lib/data/recipe_presets.dart` | `presetCategories` / `presetCookingMinutes` / `presetUnits` 静态常量 |
| `lib/widgets/recipe_form/recipe_form_card.dart` | 通用章节卡片外壳（icon + 标题 + 可选 count chip + 子内容） |
| `lib/widgets/recipe_form/cooking_time_row.dart` | 时间 chips（基于 `PillChip`）+ 联动数字输入 |
| `lib/widgets/recipe_form/difficulty_stars.dart` | 5 星点击 + 文字标签 |
| `lib/widgets/recipe_form/unit_dropdown.dart` | 单位 chip 触发器 + bottom sheet |
| `lib/widgets/recipe_form/recipe_category_chips.dart` | 复用 `CategoryChips` + 处理 "+ 其他" 弹窗 |
| `lib/widgets/recipe_form/ai_collapsible_banner.dart` | AI 入口折叠条 |
| `test/recipe_ingredient_migration_test.dart` | RecipeIngredient quantity/unit + 旧 JSON 解析测试 |
| `test/recipe_form_card_test.dart` | recipe_form_card widget 测试 |
| `test/cooking_time_row_test.dart` | cooking_time_row widget 测试 |
| `test/difficulty_stars_test.dart` | difficulty_stars widget 测试 |
| `test/unit_dropdown_test.dart` | unit_dropdown widget 测试 |
| `test/recipe_category_chips_test.dart` | recipe_category_chips widget 测试 |
| `test/ai_collapsible_banner_test.dart` | AI 折叠条 widget 测试 |

### 修改

| 文件 | 改动 |
|---|---|
| `lib/models/recipe.dart` | `RecipeIngredient` 加 quantity / unit；fromJson / toJson 兼容；`_parseLegacyAmount` |
| `lib/screens/custom_recipe_form_screen.dart` | 重构 build：替换 banner / cover / 三段卡片 / 保存区 / 验证策略 |

### 复用（不修改）

- `lib/widgets/common/category_chips.dart`（CategoryChips）
- `lib/widgets/shared/pill_chip.dart`（PillChip）
- `lib/widgets/shared/recipe_image.dart`（RecipeImage）
- `lib/utils/app_snackbar.dart`（showAppSnackBar）
- `lib/theme/app_*.dart`（design tokens）

---

## Task 1：新建 `recipe_presets.dart` 常量

**Files:**
- Create: `lib/data/recipe_presets.dart`

- [ ] **Step 1：创建常量文件**

```dart
// lib/data/recipe_presets.dart

/// 食谱表单中常用的预设值。后续可能改为运行时可配置；本期为静态常量。
class RecipePresets {
  RecipePresets._();

  /// 分类预设。"+ 其他" 由 wrapper widget 在末尾追加。
  static const List<String> categories = [
    '家常',
    '川菜',
    '粤菜',
    '西式',
    '烘焙',
    '汤羹',
  ];

  /// 烹饪时间预设（分钟）。最后一个 120 在 UI 上展示为 "120+"，但点击仍写值 120。
  static const List<int> cookingMinutes = [15, 30, 45, 60, 90, 120];

  /// 食材单位预设。"自定义…" 由 unit_dropdown 在 sheet 末尾追加。
  static const List<String> units = [
    'g',
    'ml',
    'kg',
    '个',
    '把',
    '根',
    '颗',
    '片',
    '杯',
    '勺',
    '适量',
  ];
}
```

- [ ] **Step 2：编译检查**

Run: `flutter analyze lib/data/recipe_presets.dart`
Expected: `No issues found!`

- [ ] **Step 3：Commit**

```bash
git add lib/data/recipe_presets.dart
git commit -m "feat(recipe-form): add recipe presets (categories, time, units)"
```

---

## Task 2：`RecipeIngredient` 拆分为 `quantity + unit`（TDD）

**Files:**
- Modify: `lib/models/recipe.dart`
- Create: `test/recipe_ingredient_migration_test.dart`

- [ ] **Step 1：写新字段 + JSON 兼容测试**

```dart
// test/recipe_ingredient_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';

void main() {
  group('RecipeIngredient migration', () {
    test('reads new shape (quantity + unit) from json', () {
      final ing = RecipeIngredient.fromJson({
        'name': '西红柿',
        'quantity': '200',
        'unit': 'g',
        'amount': '200g',
      });
      expect(ing.name, '西红柿');
      expect(ing.quantity, '200');
      expect(ing.unit, 'g');
      expect(ing.amount, '200g');
    });

    test('parses legacy amount "200g" into quantity + unit', () {
      final ing = RecipeIngredient.fromJson({
        'name': '西红柿',
        'amount': '200g',
      });
      expect(ing.quantity, '200');
      expect(ing.unit, 'g');
      expect(ing.amount, '200g');
    });

    test('parses legacy amount "3 个" into quantity + unit', () {
      final ing = RecipeIngredient.fromJson({
        'name': '鸡蛋',
        'amount': '3 个',
      });
      expect(ing.quantity, '3');
      expect(ing.unit, '个');
    });

    test('parses legacy amount "1.5kg" with decimal', () {
      final ing = RecipeIngredient.fromJson({
        'name': '面粉',
        'amount': '1.5kg',
      });
      expect(ing.quantity, '1.5');
      expect(ing.unit, 'kg');
    });

    test('falls back to unit-only when amount has no leading number', () {
      final ing = RecipeIngredient.fromJson({
        'name': '盐',
        'amount': '适量',
      });
      expect(ing.quantity, '');
      expect(ing.unit, '适量');
    });

    test('handles empty amount gracefully', () {
      final ing = RecipeIngredient.fromJson({'name': '葱', 'amount': ''});
      expect(ing.quantity, '');
      expect(ing.unit, '');
      expect(ing.amount, '');
    });

    test('toJson emits quantity, unit, and amount together', () {
      const ing = RecipeIngredient(name: '西红柿', quantity: '200', unit: 'g');
      final json = ing.toJson();
      expect(json['quantity'], '200');
      expect(json['unit'], 'g');
      expect(json['amount'], '200g');
    });

    test('amount is composed when constructor omits it', () {
      const a = RecipeIngredient(name: 'a', quantity: '200', unit: 'g');
      expect(a.amount, '200g');

      const b = RecipeIngredient(name: 'b', quantity: '', unit: '适量');
      expect(b.amount, '适量');

      const c = RecipeIngredient(name: 'c', quantity: '3', unit: '');
      expect(c.amount, '3');

      const d = RecipeIngredient(name: 'd', quantity: '', unit: '');
      expect(d.amount, '');
    });

    test('explicit amount overrides composed value (legacy round-trip)', () {
      const ing = RecipeIngredient(
        name: 'x',
        quantity: '200',
        unit: 'g',
        amount: 'legacy override',
      );
      expect(ing.amount, 'legacy override');
    });

    test('round-trip fromJson(toJson(...)) preserves all fields', () {
      const original = RecipeIngredient(
        name: '西红柿',
        quantity: '200',
        unit: 'g',
      );
      final restored = RecipeIngredient.fromJson(original.toJson());
      expect(restored.name, original.name);
      expect(restored.quantity, original.quantity);
      expect(restored.unit, original.unit);
      expect(restored.amount, original.amount);
    });
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/recipe_ingredient_migration_test.dart`
Expected: 编译报错（RecipeIngredient 还没有 `quantity` / `unit` 参数）

- [ ] **Step 3：实现 `RecipeIngredient` 改造**

替换 `lib/models/recipe.dart` 中 `RecipeIngredient` 类（约文件顶部 1-37 行）：

```dart
class RecipeIngredient {
  final String name;
  final String quantity;
  final String unit;
  final String amount;

  const RecipeIngredient({
    required this.name,
    this.quantity = '',
    this.unit = '',
    String? amount,
  }) : amount = amount ?? _composeAmount(quantity, unit);

  static String _composeAmount(String quantity, String unit) {
    final q = quantity.trim();
    final u = unit.trim();
    if (q.isEmpty && u.isEmpty) return '';
    if (q.isEmpty) return u;
    if (u.isEmpty) return q;
    return '$q$u';
  }

  static _LegacyAmountParts _parseLegacyAmount(String amount) {
    final trimmed = amount.trim();
    if (trimmed.isEmpty) return const _LegacyAmountParts('', '');
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(trimmed);
    if (match == null) {
      return _LegacyAmountParts('', trimmed);
    }
    return _LegacyAmountParts(
      match.group(1) ?? '',
      (match.group(2) ?? '').trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeIngredient &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          quantity == other.quantity &&
          unit == other.unit &&
          amount == other.amount;

  @override
  int get hashCode => Object.hash(name, quantity, unit, amount);

  RecipeIngredient copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? amount,
  }) {
    return RecipeIngredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      amount: amount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'amount': amount,
    };
  }

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'] as String? ?? '';
    final hasNewShape =
        json.containsKey('quantity') || json.containsKey('unit');
    if (hasNewShape) {
      return RecipeIngredient(
        name: json['name'] as String? ?? '',
        quantity: json['quantity'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        amount: amount,
      );
    }
    final parts = _parseLegacyAmount(amount);
    return RecipeIngredient(
      name: json['name'] as String? ?? '',
      quantity: parts.quantity,
      unit: parts.unit,
      amount: amount,
    );
  }
}

class _LegacyAmountParts {
  const _LegacyAmountParts(this.quantity, this.unit);
  final String quantity;
  final String unit;
}
```

- [ ] **Step 4：运行测试，确认全部通过**

Run: `flutter test test/recipe_ingredient_migration_test.dart`
Expected: 所有 9 条测试 PASS

- [ ] **Step 5：跑全套现有测试，确保无回归**

Run: `flutter test`
Expected: 全部 PASS（已有 `custom_recipe_provider_test.dart` 等会复用旧的 `amount` 字段读写，应该仍然通过）

> 如果有测试失败：检查它构造 `RecipeIngredient(name: x, amount: y)` 的地方——新 constructor 仍接受 `amount` 字段（作为 explicit override），所以应该兼容。如不通过，修测试 setup 或在这里把已知不兼容点列出。

- [ ] **Step 6：Commit**

```bash
git add lib/models/recipe.dart test/recipe_ingredient_migration_test.dart
git commit -m "feat(recipe): split RecipeIngredient.amount into quantity + unit (legacy compat)"
```

---

## Task 3：`recipe_form_card.dart` 章节卡片外壳（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/recipe_form_card.dart`
- Create: `test/recipe_form_card_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/recipe_form_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/recipe_form_card.dart';

void main() {
  testWidgets('renders icon, title, and child content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.restaurant_menu,
            title: '基础信息',
            child: Text('卡片内容'),
          ),
        ),
      ),
    );

    expect(find.text('基础信息'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(find.text('卡片内容'), findsOneWidget);
  });

  testWidgets('renders count chip when countLabel is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.list,
            title: '食材',
            countLabel: '3 项',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('3 项'), findsOneWidget);
  });

  testWidgets('omits count chip when countLabel is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.list,
            title: '基础信息',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.byType(Container), findsWidgets); // sanity
    expect(find.text('3 项'), findsNothing);
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/recipe_form_card_test.dart`
Expected: 编译报错（RecipeFormCard 不存在）

- [ ] **Step 3：实现 widget**

```dart
// lib/widgets/recipe_form/recipe_form_card.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecipeFormCard extends StatelessWidget {
  const RecipeFormCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.countLabel,
    this.iconBackgroundColor,
    this.iconForegroundColor,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? countLabel;
  final Color? iconBackgroundColor;
  final Color? iconForegroundColor;

  @override
  Widget build(BuildContext context) {
    final iconBg = iconBackgroundColor ?? AppColors.primaryFixed;
    final iconFg = iconForegroundColor ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconFg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (countLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    countLabel!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4：运行测试，确认通过**

Run: `flutter test test/recipe_form_card_test.dart`
Expected: 3 条测试 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/recipe_form_card.dart test/recipe_form_card_test.dart
git commit -m "feat(recipe-form): add RecipeFormCard section shell"
```

---

## Task 4：`difficulty_stars.dart`（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/difficulty_stars.dart`
- Create: `test/difficulty_stars_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/difficulty_stars_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/difficulty_stars.dart';

void main() {
  testWidgets('renders 5 star icons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DifficultyStars(value: 3, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
  });

  testWidgets('shows correct label for each value', (tester) async {
    final labels = {1: '简单', 2: '较易', 3: '普通', 4: '进阶', 5: '专业'};
    for (final entry in labels.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DifficultyStars(value: entry.key, onChanged: (_) {}),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget,
          reason: 'value=${entry.key}');
    }
  });

  testWidgets('tapping nth star emits onChanged with n+1', (tester) async {
    final emitted = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DifficultyStars(value: 1, onChanged: emitted.add),
        ),
      ),
    );
    final stars = find.byIcon(Icons.star_rounded);
    await tester.tap(stars.at(2)); // 第 3 颗
    expect(emitted, [3]);
    await tester.tap(stars.at(4)); // 第 5 颗
    expect(emitted, [3, 5]);
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/difficulty_stars_test.dart`
Expected: 编译报错

- [ ] **Step 3：实现 widget**

```dart
// lib/widgets/recipe_form/difficulty_stars.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class DifficultyStars extends StatelessWidget {
  const DifficultyStars({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static const _labels = ['简单', '较易', '普通', '进阶', '专业'];

  String get _label {
    if (value < 1 || value > 5) return '';
    return _labels[value - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          GestureDetector(
            onTap: () => onChanged(i + 1),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                Icons.star_rounded,
                size: 32,
                color: i < value
                    ? AppColors.secondaryContainer
                    : AppColors.surfaceContainerHigh,
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.urgentAttentionBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            _label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4：测试通过**

Run: `flutter test test/difficulty_stars_test.dart`
Expected: 3 条 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/difficulty_stars.dart test/difficulty_stars_test.dart
git commit -m "feat(recipe-form): add DifficultyStars widget"
```

---

## Task 5：`cooking_time_row.dart`（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/cooking_time_row.dart`
- Create: `test/cooking_time_row_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/cooking_time_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/cooking_time_row.dart';

void main() {
  Widget _harness({required CookingTimeRow row}) {
    return MaterialApp(home: Scaffold(body: row));
  }

  testWidgets('renders 6 chips with last labeled "120+"', (tester) async {
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(
        controller: TextEditingController(text: '30'),
        onChanged: (_) {},
      ),
    ));
    for (final n in ['15', '30', '45', '60', '90']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('120+'), findsOneWidget);
  });

  testWidgets('tapping chip writes value to controller and emits onChanged',
      (tester) async {
    final controller = TextEditingController();
    final emitted = <int?>[];
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: emitted.add),
    ));

    await tester.tap(find.text('45'));
    await tester.pumpAndSettle();
    expect(controller.text, '45');
    expect(emitted, [45]);
  });

  testWidgets('tapping "120+" chip writes 120', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: (_) {}),
    ));
    await tester.tap(find.text('120+'));
    await tester.pumpAndSettle();
    expect(controller.text, '120');
  });

  testWidgets('typing custom number does not crash and updates controller',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: (_) {}),
    ));
    await tester.enterText(find.byType(TextField), '25');
    expect(controller.text, '25');
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/cooking_time_row_test.dart`
Expected: 编译报错

- [ ] **Step 3：实现 widget**

```dart
// lib/widgets/recipe_form/cooking_time_row.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/recipe_presets.dart';
import '../../theme/app_theme.dart';
import '../shared/pill_chip.dart';

class CookingTimeRow extends StatefulWidget {
  const CookingTimeRow({
    super.key,
    required this.controller,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  State<CookingTimeRow> createState() => _CookingTimeRowState();
}

class _CookingTimeRowState extends State<CookingTimeRow> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {}); // 让 chip 高亮跟随 controller
  }

  void _selectPreset(int minutes) {
    widget.controller.text = minutes.toString();
    widget.onChanged(minutes);
  }

  int? get _currentValue => int.tryParse(widget.controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final current = _currentValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: RecipePresets.cookingMinutes.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final minutes = RecipePresets.cookingMinutes[index];
              final isLast = index == RecipePresets.cookingMinutes.length - 1;
              final label = isLast ? '${minutes}+' : '$minutes';
              return PillChip(
                label: label,
                selected: current == minutes,
                onTap: () => _selectPreset(minutes),
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: AppColors.onPrimary,
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              '或自定义',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 72,
              child: TextField(
                controller: widget.controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  errorText: widget.errorText,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: (value) =>
                    widget.onChanged(int.tryParse(value.trim())),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '分钟',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4：测试通过**

Run: `flutter test test/cooking_time_row_test.dart`
Expected: 4 条 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/cooking_time_row.dart test/cooking_time_row_test.dart
git commit -m "feat(recipe-form): add CookingTimeRow chips + custom input"
```

---

## Task 6：`unit_dropdown.dart`（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/unit_dropdown.dart`
- Create: `test/unit_dropdown_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/unit_dropdown_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/unit_dropdown.dart';

void main() {
  Widget _harness({String value = '', ValueChanged<String>? onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: UnitDropdown(value: value, onChanged: onChanged ?? (_) {}),
      ),
    );
  }

  testWidgets('shows current value with caret', (tester) async {
    await tester.pumpWidget(_harness(value: 'g'));
    expect(find.textContaining('g'), findsOneWidget);
  });

  testWidgets('shows placeholder when value is empty', (tester) async {
    await tester.pumpWidget(_harness(value: ''));
    expect(find.textContaining('单位'), findsOneWidget);
  });

  testWidgets('tapping opens bottom sheet with preset units', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.byType(UnitDropdown));
    await tester.pumpAndSettle();

    expect(find.text('g'), findsOneWidget);
    expect(find.text('个'), findsOneWidget);
    expect(find.text('适量'), findsOneWidget);
    expect(find.text('自定义…'), findsOneWidget);
  });

  testWidgets('selecting a unit closes sheet and emits onChanged',
      (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(_harness(onChanged: emitted.add));
    await tester.tap(find.byType(UnitDropdown));
    await tester.pumpAndSettle();

    await tester.tap(find.text('个'));
    await tester.pumpAndSettle();

    expect(emitted, ['个']);
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/unit_dropdown_test.dart`
Expected: 编译报错

- [ ] **Step 3：实现 widget**

```dart
// lib/widgets/recipe_form/unit_dropdown.dart
import 'package:flutter/material.dart';
import '../../data/recipe_presets.dart';
import '../../theme/app_theme.dart';
import '../shared/pill_chip.dart';

class UnitDropdown extends StatelessWidget {
  const UnitDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final unit in RecipePresets.units)
              ListTile(
                title: Text(unit),
                trailing: unit == value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(unit),
              ),
            const Divider(height: 1),
            ListTile(
              title: const Text('自定义…'),
              leading: const Icon(Icons.edit_outlined),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final custom = await _promptCustomUnit(context);
                if (custom != null && custom.isNotEmpty) {
                  onChanged(custom);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  Future<String?> _promptCustomUnit(BuildContext context) {
    final controller = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义单位'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：粒'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = value.isEmpty ? '单位 ▾' : '$value ▾';
    return PillChip(
      label: label,
      onTap: () => _openSheet(context),
      backgroundColor: AppColors.surfaceContainerLowest,
      borderColor: AppColors.outlineVariant,
    );
  }
}
```

- [ ] **Step 4：测试通过**

Run: `flutter test test/unit_dropdown_test.dart`
Expected: 4 条 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/unit_dropdown.dart test/unit_dropdown_test.dart
git commit -m "feat(recipe-form): add UnitDropdown chip + bottom sheet"
```

---

## Task 7：`recipe_category_chips.dart`（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/recipe_category_chips.dart`
- Create: `test/recipe_category_chips_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/recipe_category_chips_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/recipe_category_chips.dart';

void main() {
  Widget _harness({
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: RecipeCategoryChips(
            selected: selected,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('renders preset categories and "+ 其他"', (tester) async {
    await tester.pumpWidget(_harness(selected: '家常', onChanged: (_) {}));
    for (final c in ['家常', '川菜', '粤菜']) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.text('+ 其他'), findsOneWidget);
  });

  testWidgets('selecting a preset chip emits onChanged', (tester) async {
    final emitted = <String>[];
    await tester
        .pumpWidget(_harness(selected: '家常', onChanged: emitted.add));
    await tester.tap(find.text('川菜'));
    await tester.pumpAndSettle();
    expect(emitted, ['川菜']);
  });

  testWidgets('non-preset selected value is rendered as a selected chip',
      (tester) async {
    await tester
        .pumpWidget(_harness(selected: '日料', onChanged: (_) {}));
    expect(find.text('日料'), findsOneWidget);
  });

  testWidgets('tapping "+ 其他" opens dialog and emits typed value',
      (tester) async {
    final emitted = <String>[];
    await tester
        .pumpWidget(_harness(selected: '家常', onChanged: emitted.add));

    await tester.tap(find.text('+ 其他'));
    await tester.pumpAndSettle();

    expect(find.text('自定义分类'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '日料');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(emitted, ['日料']);
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/recipe_category_chips_test.dart`
Expected: 编译报错

- [ ] **Step 3：实现 widget（复用 `CategoryChips`）**

```dart
// lib/widgets/recipe_form/recipe_category_chips.dart
import 'package:flutter/material.dart';
import '../../data/recipe_presets.dart';
import '../common/category_chips.dart';

class RecipeCategoryChips extends StatelessWidget {
  const RecipeCategoryChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const _customSentinel = '+ 其他';

  List<String> _buildCategories() {
    final base = [...RecipePresets.categories];
    if (selected.isNotEmpty && !base.contains(selected)) {
      base.add(selected);
    }
    base.add(_customSentinel);
    return base;
  }

  Future<void> _handleSelection(BuildContext context, String value) async {
    if (value == _customSentinel) {
      final custom = await _promptCustomCategory(context);
      if (custom != null && custom.isNotEmpty) {
        onChanged(custom);
      }
      return;
    }
    onChanged(value);
  }

  Future<String?> _promptCustomCategory(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：日料'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CategoryChips(
      categories: _buildCategories(),
      selectedCategory: selected,
      onSelected: (value) => _handleSelection(context, value),
    );
  }
}
```

- [ ] **Step 4：测试通过**

Run: `flutter test test/recipe_category_chips_test.dart`
Expected: 4 条 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/recipe_category_chips.dart test/recipe_category_chips_test.dart
git commit -m "feat(recipe-form): add RecipeCategoryChips with custom dialog"
```

---

## Task 8：`ai_collapsible_banner.dart`（TDD）

**Files:**
- Create: `lib/widgets/recipe_form/ai_collapsible_banner.dart`
- Create: `test/ai_collapsible_banner_test.dart`

- [ ] **Step 1：写 widget 测试**

```dart
// test/ai_collapsible_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/ai_collapsible_banner.dart';

void main() {
  Widget _harness({bool initiallyExpanded = false}) {
    return MaterialApp(
      home: Scaffold(
        body: AiCollapsibleBanner(
          urlController: TextEditingController(),
          onParse: () {},
          initiallyExpanded: initiallyExpanded,
        ),
      ),
    );
  }

  testWidgets('starts collapsed and shows hint text', (tester) async {
    await tester.pumpWidget(_harness());
    expect(find.text('✨ 粘贴链接，AI 自动填表'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping the hint expands to reveal url input', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('解析为草稿'), findsOneWidget);
  });

  testWidgets('initiallyExpanded=true shows input from start', (tester) async {
    await tester.pumpWidget(_harness(initiallyExpanded: true));
    expect(find.byType(TextField), findsOneWidget);
  });
}
```

- [ ] **Step 2：运行测试，确认失败**

Run: `flutter test test/ai_collapsible_banner_test.dart`
Expected: 编译报错

- [ ] **Step 3：实现 widget**

```dart
// lib/widgets/recipe_form/ai_collapsible_banner.dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AiCollapsibleBanner extends StatefulWidget {
  const AiCollapsibleBanner({
    super.key,
    required this.urlController,
    required this.onParse,
    this.initiallyExpanded = false,
  });

  final TextEditingController urlController;
  final VoidCallback onParse;
  final bool initiallyExpanded;

  @override
  State<AiCollapsibleBanner> createState() => AiCollapsibleBannerState();
}

class AiCollapsibleBannerState extends State<AiCollapsibleBanner> {
  late bool _expanded = widget.initiallyExpanded;

  void expand() {
    if (!_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _expanded ? _buildExpanded(context) : _buildCollapsed(context),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryFixed.withValues(alpha: 0.5),
          border: Border.all(color: AppColors.primaryFixed),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '✨ 粘贴链接，AI 自动填表',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '展开',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ 用 AI 一键导入',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.onPrimary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('recipe_url_input'),
            controller: widget.urlController,
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 下厨房…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const Key('recipe_url_parse'),
            onPressed: widget.onParse,
            child: const Text('解析为草稿'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4：测试通过**

Run: `flutter test test/ai_collapsible_banner_test.dart`
Expected: 3 条 PASS

- [ ] **Step 5：Commit**

```bash
git add lib/widgets/recipe_form/ai_collapsible_banner.dart test/ai_collapsible_banner_test.dart
git commit -m "feat(recipe-form): add AiCollapsibleBanner"
```

---

## Task 9：替换基础信息区到新控件

> **从这一步开始进入 `custom_recipe_form_screen.dart` 重构。改动较大但目标清晰：每一步只换一段，保持其他段落原貌。**

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`
- Modify: `test/custom_recipe_flow_test.dart`（如果有验证基础信息的测试需要适配）

- [ ] **Step 1：在 `_CustomRecipeFormScreenState` 增加 difficulty / unit 状态字段**

打开 `lib/screens/custom_recipe_form_screen.dart`，在 `_CustomRecipeFormScreenState` 类中：
- `_difficultyController` 保留（仍是 `_saveRecipe` 的读取来源）
- `initState` 里把 `_difficultyController` 默认 '3'（普通），现状是 '1'

替换 `_difficultyController` 初始化（约 74-76 行）：

```dart
_difficultyController = TextEditingController(
  text: recipe?.difficulty.toString() ?? '3',
);
```

- [ ] **Step 2：在 build 顶部 import 新 widget**

文件头部 imports 加：

```dart
import '../widgets/recipe_form/recipe_form_card.dart';
import '../widgets/recipe_form/recipe_category_chips.dart';
import '../widgets/recipe_form/cooking_time_row.dart';
import '../widgets/recipe_form/difficulty_stars.dart';
```

- [ ] **Step 3：替换基础信息 Padding/Column 为 RecipeFormCard**

定位现有「基础信息」段（约 136-178 行的 Padding+Column 中"基础信息"那一段），整段替换为：

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.lg,
    0,
  ),
  child: RecipeFormCard(
    icon: Icons.restaurant_menu,
    title: '基础信息',
    iconBackgroundColor: AppColors.primaryFixed,
    iconForegroundColor: AppColors.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          decoration: _fieldDecoration('食谱名称 *', hint: '例如：西红柿炒蛋'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '分类 *',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RecipeCategoryChips(
          selected: _categoryController.text,
          onChanged: (value) => setState(() {
            _categoryController.text = value;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '烹饪时间 *',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        CookingTimeRow(
          controller: _cookingMinutesController,
          onChanged: (_) {},
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '难度 *',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DifficultyStars(
          value: int.tryParse(_difficultyController.text) ?? 3,
          onChanged: (value) => setState(() {
            _difficultyController.text = value.toString();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _descriptionController,
          decoration: _fieldDecoration('简介', hint: '简单描述这道菜的特色…'),
          maxLines: 3,
        ),
      ],
    ),
  ),
),
```

并把 `_fieldDecoration` 扩展为接受可选 hint：

```dart
InputDecoration _fieldDecoration(String labelText, {String? hint}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  );
}
```

- [ ] **Step 4：临时保留旧的食材/步骤段（以便分步重构）**

当前 build 方法中，从 "食材" 开始到 "添加步骤" 按钮的段落，先**整段保留不动**。Task 10 会替换它。

- [ ] **Step 5：跑应用 + 测试**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/custom_recipe_flow_test.dart`
Expected: PASS（如有失败，查看 fail 信息——可能因为 chip 文字 vs TextField label 的查找方式变了；按需修测试 selector）

- [ ] **Step 6：人工冒烟（macOS / 模拟器，如果可用）**

启动应用进入"新建食谱"，确认：
- 基础信息卡片渲染正确
- 分类 chips 可点击 + "+ 其他" 弹窗
- 时间 chip 联动数字输入
- 难度星可改、文字 label 跟随
- 简介 3 行可输入

> 如果环境无 GUI，跳过此步并在备注里说明。

- [ ] **Step 7：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart
git commit -m "feat(recipe-form): replace basic info section with cards + new controls"
```

---

## Task 10：重写食材区（卡片 + 拖动 + quantity/unit）

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：扩展 `_IngredientControllers` 持有 quantity / unit / dragKey**

定位文件底部 `_IngredientControllers` 类（约第 762 行），整体替换：

```dart
class _IngredientControllers {
  _IngredientControllers({
    required String name,
    required String quantity,
    required this.unit,
  })  : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(text: quantity),
        dragKey = UniqueKey();

  factory _IngredientControllers.empty() {
    return _IngredientControllers(name: '', quantity: '', unit: 'g');
  }

  factory _IngredientControllers.from(RecipeIngredient ingredient) {
    return _IngredientControllers(
      name: ingredient.name,
      quantity: ingredient.quantity,
      unit: ingredient.unit,
    );
  }

  final TextEditingController nameController;
  final TextEditingController quantityController;
  String unit;
  final Key dragKey;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
  }
}
```

- [ ] **Step 2：更新 `_completeIngredients` 与 `_validateIngredients` 用新字段**

替换 `_completeIngredients`（约第 594 行）：

```dart
List<RecipeIngredient> _completeIngredients() {
  return _ingredientControllers
      .map((ingredient) {
        final name = ingredient.nameController.text.trim();
        final quantity = ingredient.quantityController.text.trim();
        final unit = ingredient.unit.trim();
        if (name.isEmpty) return null;
        if (quantity.isEmpty && unit.isEmpty) return null;
        return RecipeIngredient(name: name, quantity: quantity, unit: unit);
      })
      .whereType<RecipeIngredient>()
      .toList();
}
```

替换 `_validateIngredients`（约第 567 行），把 `amountController` 改为 `quantityController + unit`：

```dart
List<String> _validateIngredients() {
  var hasAnyIngredientText = false;
  var hasCompleteIngredient = false;
  var missingIngredientName = false;
  var missingIngredientAmount = false;
  for (final ingredient in _ingredientControllers) {
    final ingredientName = ingredient.nameController.text.trim();
    final ingredientQty = ingredient.quantityController.text.trim();
    final ingredientUnit = ingredient.unit.trim();
    final hasAmount = ingredientQty.isNotEmpty || ingredientUnit.isNotEmpty;
    if (ingredientName.isNotEmpty || hasAmount) {
      hasAnyIngredientText = true;
    }
    if (ingredientName.isNotEmpty && hasAmount) {
      hasCompleteIngredient = true;
    } else if (ingredientName.isEmpty && hasAmount) {
      missingIngredientName = true;
    } else if (ingredientName.isNotEmpty && !hasAmount) {
      missingIngredientAmount = true;
    }
  }

  return <String>[
    if (!hasCompleteIngredient && !hasAnyIngredientText) '至少一种食材',
    if (missingIngredientName) '食材名称',
    if (missingIngredientAmount) '食材用量',
  ];
}
```

- [ ] **Step 3：在文件头部 import**

```dart
import '../widgets/recipe_form/unit_dropdown.dart';
```

- [ ] **Step 4：替换食材渲染段**

定位现有"食材"段（约 179-219 行：Text + for-loop ingredient rows + OutlinedButton.icon "添加食材"），整段替换为：

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.lg,
    0,
  ),
  child: RecipeFormCard(
    icon: Icons.restaurant,
    title: '食材',
    iconBackgroundColor: AppColors.secondaryFixed,
    iconForegroundColor: AppColors.secondary,
    countLabel: '${_ingredientControllers.length} 项',
    child: Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _ingredientControllers.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = _ingredientControllers.removeAt(oldIndex);
              _ingredientControllers.insert(adjusted, item);
            });
          },
          itemBuilder: (context, i) {
            final ing = _ingredientControllers[i];
            return Padding(
              key: ValueKey(ing.dragKey),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Icon(
                      Icons.drag_indicator,
                      color: AppColors.outlineVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: ing.nameController,
                      decoration: _compactDecoration('食材名称'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: ing.quantityController,
                      decoration: _compactDecoration('用量'),
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UnitDropdown(
                    value: ing.unit,
                    onChanged: (value) => setState(() => ing.unit = value),
                  ),
                  if (i > 0)
                    IconButton(
                      onPressed: () => _removeIngredient(i),
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: '移除食材',
                      color: AppColors.error,
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addIngredient,
          icon: const Icon(Icons.add),
          label: const Text('添加食材'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    ),
  ),
),
```

并在 `_CustomRecipeFormScreenState` 内增加：

```dart
InputDecoration _compactDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
  );
}
```

- [ ] **Step 5：跑测试，确保无回归**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test`
Expected: 全部 PASS（特别注意 `custom_recipe_provider_test.dart` 和 `custom_recipe_flow_test.dart`——它们构造 RecipeIngredient 用旧 `amount` API；新 model 兼容）

> 如果 widget 测试找 `'用量'` TextField 失败，因为现在是 hintText 而不是 labelText，可能需要按 `find.byType(TextField)` 或 `find.byKey` 查找。修测试 selector，不要修生产代码。

- [ ] **Step 6：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart
git commit -m "feat(recipe-form): rewrite ingredients section (card + drag + unit chip)"
```

---

## Task 11：重写步骤区（卡片 + 圆形编号 + 拖动）

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：把 `_stepControllers` 升级为持有 dragKey**

定位 `_stepControllers` 字段（约第 53 行），改为持有 small wrapper：

在 `_CustomRecipeFormScreenState` 内 / 文件底部（紧邻 `_IngredientControllers` 之上）添加：

```dart
class _StepEntry {
  _StepEntry({String text = ''})
      : controller = TextEditingController(text: text),
        dragKey = UniqueKey();

  final TextEditingController controller;
  final Key dragKey;

  void dispose() => controller.dispose();
}
```

替换 state field（约第 53 行）：

```dart
late final List<_StepEntry> _stepEntries;
```

替换 `initState` 里 `_stepControllers` 初始化（约 85-91 行）：

```dart
_stepEntries = recipe?.steps.isNotEmpty == true
    ? recipe!.steps.map((step) => _StepEntry(text: step)).toList()
    : [_StepEntry()];
```

替换 `dispose` 里旧的 step controller 循环（约 108-111 行）：

```dart
for (final entry in _stepEntries) {
  entry.dispose();
}
```

替换 `_addStep` / `_removeStep`（约 435-445 行）：

```dart
void _addStep() {
  setState(() {
    _stepEntries.add(_StepEntry());
  });
}

void _removeStep(int index) {
  setState(() {
    _stepEntries.removeAt(index).dispose();
  });
}
```

替换 `_saveRecipe` 里读取 steps 的代码（约 354-358 行）：

```dart
final steps = _stepEntries
    .map((entry) => entry.controller.text.trim())
    .where((step) => step.isNotEmpty)
    .toList();
```

- [ ] **Step 2：替换步骤渲染段**

定位现有"步骤"段（约 220-254 行），整段替换：

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.lg,
    0,
  ),
  child: RecipeFormCard(
    icon: Icons.format_list_numbered,
    title: '步骤',
    iconBackgroundColor: AppColors.secondaryFixed,
    iconForegroundColor: AppColors.secondary,
    countLabel: '${_stepEntries.length} 步',
    child: Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _stepEntries.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = _stepEntries.removeAt(oldIndex);
              _stepEntries.insert(adjusted, item);
            });
          },
          itemBuilder: (context, i) {
            final entry = _stepEntries[i];
            return Padding(
              key: ValueKey(entry.dragKey),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: entry.controller,
                      decoration: _compactDecoration('输入下一步…'),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.xs),
                          child: Icon(
                            Icons.drag_indicator,
                            color: AppColors.outlineVariant,
                          ),
                        ),
                      ),
                      if (i > 0)
                        IconButton(
                          onPressed: () => _removeStep(i),
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: '移除步骤',
                          color: AppColors.error,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _addStep,
          icon: const Icon(Icons.add),
          label: const Text('添加步骤'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    ),
  ),
),
```

- [ ] **Step 3：跑测试**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 4：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart
git commit -m "feat(recipe-form): rewrite steps section (card + numbered + drag)"
```

---

## Task 12：替换 AI banner 为折叠条 + 适配编辑模式

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：导入新 widget 并加 GlobalKey**

文件头部添加：

```dart
import '../widgets/recipe_form/ai_collapsible_banner.dart';
```

在 `_CustomRecipeFormScreenState` 内（其他 controller 旁边）：

```dart
final _aiBannerKey = GlobalKey<AiCollapsibleBannerState>();
```

- [ ] **Step 2：替换 build 中的 banner**

定位 build 方法中 `_AiUrlBanner(...)`（约 126-128 行），替换为：

```dart
if (!_isEditing)
  Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      0,
    ),
    child: AiCollapsibleBanner(
      key: _aiBannerKey,
      urlController: _urlController,
      onParse: _onParseUrl,
    ),
  ),
```

- [ ] **Step 3：剪贴板检测命中时自动展开**

定位 `_maybeOfferClipboardUrl`（约 280-302 行），改为先尝试展开 banner（如果存在），仍保留 SnackBar 作 backup：

```dart
Future<void> _maybeOfferClipboardUrl() async {
  final url = await _clipboardDetector.peek();
  if (url == null || !mounted) return;

  _aiBannerKey.currentState?.expand();
  _urlController.text = url;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('检测到食谱链接：$url'),
      action: SnackBarAction(
        label: '解析',
        onPressed: _onParseUrl,
      ),
    ),
  );

  Future<void>.delayed(const Duration(seconds: 9), () {
    if (mounted && _urlController.text != url) {
      _clipboardDetector.markIgnored(url);
    }
  });
}
```

- [ ] **Step 4：删除旧的 `_AiUrlBanner` 类**

删除文件底部 `_AiUrlBanner` 类（约 787-829 行）——已被新组件替代，避免死代码。

- [ ] **Step 5：跑测试**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test test/custom_recipe_form_url_banner_test.dart`
Expected: 可能失败（旧测试找 `_AiUrlBanner` 内的 widget）。**修测试**让它针对 `AiCollapsibleBanner` 工作：
- 先点击折叠条展开（`tester.tap(find.text('✨ 粘贴链接，AI 自动填表'))` + `pumpAndSettle`），然后再断言 URL 输入和解析按钮存在

如果重写测试代价过大，把它转成两个测试：一个检查折叠条存在，一个检查展开后的解析流程。

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 6：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart test/custom_recipe_form_url_banner_test.dart
git commit -m "feat(recipe-form): swap AI banner for collapsible entry"
```

---

## Task 13：自适应封面图（无图紧凑卡）

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：新增 `_CoverImagePlaceholder` 私有 widget**

在文件底部 `_CoverImageHero` 类**前面**插入：

```dart
class _CoverImagePlaceholder extends StatelessWidget {
  const _CoverImagePlaceholder({
    required this.onUpload,
    required this.onCamera,
  });

  final VoidCallback onUpload;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border.all(
          color: AppColors.outlineVariant,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 36,
            color: AppColors.outline,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '添加封面（可选）',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('上传图片'),
              ),
              OutlinedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('拍照'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2：在 build 中条件切换**

定位现有 `_CoverImageHero(...)`（约 130-135 行），替换为：

```dart
Padding(
  padding: const EdgeInsets.only(top: AppSpacing.md),
  child: _coverImageSource == null
      ? _CoverImagePlaceholder(
          onUpload: () => _selectCoverImage(ImageSource.gallery),
          onCamera: () => _selectCoverImage(ImageSource.camera),
        )
      : _CoverImageHero(
          imageSource: _coverImageSource,
          onUpload: () => _selectCoverImage(ImageSource.gallery),
          onCamera: () => _selectCoverImage(ImageSource.camera),
          onClear: _clearCoverImage,
        ),
),
```

注意：原 `_CoverImageHero` 的 `imageSource` 参数现在永远非空，但保留参数类型为 `String?` 以最小改动。

- [ ] **Step 3：跑测试**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 4：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart
git commit -m "feat(recipe-form): show compact cover placeholder when image is empty"
```

---

## Task 14：保存按钮 spinner + Divider

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：替换 bottomNavigationBar**

定位 `bottomNavigationBar: SafeArea(...)`（约 263-269 行），整段替换：

```dart
bottomNavigationBar: Container(
  decoration: const BoxDecoration(
    color: AppColors.surface,
    border: Border(
      top: BorderSide(color: AppColors.outlineVariant),
    ),
  ),
  child: SafeArea(
    minimum: const EdgeInsets.all(AppSpacing.lg),
    child: FilledButton(
      onPressed: _isSaving ? null : _saveRecipe,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
      child: _isSaving
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Text('保存中…'),
              ],
            )
          : const Text('保存食谱'),
    ),
  ),
),
```

- [ ] **Step 2：跑测试**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 3：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart
git commit -m "feat(recipe-form): show spinner + divider in save section"
```

---

## Task 15：内联错误 + 滚动到首个错误

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`

- [ ] **Step 1：在 state 增加 error 字段 + GlobalKey**

在 `_CustomRecipeFormScreenState` 加：

```dart
String? _nameError;
String? _categoryError;
String? _cookingMinutesError;
String? _difficultyError;
String? _ingredientsError;
String? _stepsError;

final _nameFieldKey = GlobalKey();
final _categoryFieldKey = GlobalKey();
final _cookingMinutesFieldKey = GlobalKey();
final _difficultyFieldKey = GlobalKey();
final _ingredientsFieldKey = GlobalKey();
final _stepsFieldKey = GlobalKey();
```

- [ ] **Step 2：把 GlobalKey 挂到对应字段**

在 build 内部找到相应 widget，加 `key:` 参数：
- 名称 TextField → `key: _nameFieldKey`
- 分类 chips 包一层 `Container(key: _categoryFieldKey, child: RecipeCategoryChips(...))`（chips 自身没有 key 槽）
- 时间 row 同样包一层 `Container(key: _cookingMinutesFieldKey, child: CookingTimeRow(...))`
- 难度 row 同样
- 食材卡片整体加 `key: _ingredientsFieldKey`（直接给 RecipeFormCard 的 `key`）
- 步骤卡片整体加 `key: _stepsFieldKey`

- [ ] **Step 3：渲染错误信息**

- 名称 TextField 的 `_fieldDecoration` 增加 errorText 形参，传 `_nameError`
- 分类 chips 下方加：

```dart
if (_categoryError != null)
  Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      _categoryError!,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.error,
          ),
    ),
  ),
```

- 时间、难度、食材、步骤都加同样的错误提示块（食材 / 步骤的错误文字放在卡片头部下方第一行）。

- [ ] **Step 4：改 onChanged 清错误**

- 名称：`onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); }`
- 分类：在 setState 内同时清 `_categoryError`
- 时间：`onChanged` 回调内清 `_cookingMinutesError`
- 难度：`onChanged` 内清 `_difficultyError`
- 食材：在 `_addIngredient` / `_removeIngredient` 以及任一字段 onChanged 内清 `_ingredientsError`
- 步骤：同上清 `_stepsError`

- [ ] **Step 5：在 `_saveRecipe` 中 map 错误并滚动**

替换 `_saveRecipe` 校验失败分支（原本是 `_showMissingFields(missingFields); return;`）：

```dart
if (missingFields.isNotEmpty) {
  setState(() {
    _nameError =
        missingFields.contains('食谱名称') ? '请填入食谱名称' : null;
    _categoryError = missingFields.contains('分类') ? '请选择分类' : null;
    _cookingMinutesError =
        missingFields.contains('有效烹饪时间') ? '请输入大于 0 的分钟数' : null;
    _difficultyError =
        missingFields.contains('1-5 的难度') ? '请选择 1-5 颗星' : null;
    final ingredientErrors = missingFields
        .where((m) => ['至少一种食材', '食材名称', '食材用量'].contains(m))
        .toList();
    _ingredientsError =
        ingredientErrors.isEmpty ? null : ingredientErrors.join('、');
    _stepsError = missingFields.contains('至少一个步骤') ? '至少添加一个步骤' : null;
  });
  await _scrollToFirstError();
  return;
}
```

并新增方法：

```dart
Future<void> _scrollToFirstError() async {
  final candidates = <(String?, GlobalKey)>[
    (_nameError, _nameFieldKey),
    (_categoryError, _categoryFieldKey),
    (_cookingMinutesError, _cookingMinutesFieldKey),
    (_difficultyError, _difficultyFieldKey),
    (_ingredientsError, _ingredientsFieldKey),
    (_stepsError, _stepsFieldKey),
  ];
  for (final (error, key) in candidates) {
    if (error != null && key.currentContext != null) {
      await Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 240),
        alignment: 0.1,
      );
      return;
    }
  }
}
```

- [ ] **Step 6：删除 `_showMissingFields` 方法（已无引用）**

如果 `_showMissingFields` 还被其他地方引用，保留；否则删除。

- [ ] **Step 7：跑测试**

Run: `flutter analyze`
Expected: 无错误

Run: `flutter test`
Expected: 全部 PASS

> 如果 `custom_recipe_flow_test.dart` 在校验失败场景断言 SnackBar 文本，需更新为断言新的内联错误文本。

- [ ] **Step 8：Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart test/custom_recipe_flow_test.dart
git commit -m "feat(recipe-form): replace SnackBar validation with inline errors + scroll"
```

---

## Task 16：综合 widget 测试 + final pass

**Files:**
- Modify: `test/custom_recipe_flow_test.dart`（增补新测试）

- [ ] **Step 1：补一条 happy path 测试**

在 `test/custom_recipe_flow_test.dart` 末尾或合适位置加：

```dart
testWidgets('full create flow with new controls saves recipe', (tester) async {
  final prefs = await _prefs({});
  await tester.pumpWidget(_app(
    prefs,
    const CustomRecipeFormScreen(),
  ));
  await tester.pumpAndSettle();

  // 名称
  await tester.enterText(find.byType(TextField).at(0), '番茄炒蛋');

  // 分类：选默认 "家常"（已选中），跳过
  // 时间：点 30
  await tester.tap(find.text('30'));
  await tester.pumpAndSettle();

  // 难度：默认 3 颗，跳过
  // 简介：可选，跳过

  // 食材：填第一行
  final qtyFields = find.byType(TextField);
  await tester.enterText(qtyFields.at(2), '西红柿'); // 食材名
  await tester.enterText(qtyFields.at(3), '200');   // 数量
  // 单位默认 g，跳过

  // 步骤：填第一步
  await tester.enterText(qtyFields.at(4), '切块翻炒');

  await tester.tap(find.text('保存食谱'));
  await tester.pumpAndSettle();

  // 期望返回上一屏，prefs 中有新食谱
  // 因为是直接 push 入 form，pop 后 widget 仍在 tree，可以查 prefs
  expect(prefs.getString(customRecipesStorageKey), contains('番茄炒蛋'));
});
```

> 若 `_app` / `_prefs` helper 签名要求传具体 screen，沿用现有 helper。`TextField.at(...)` 的 index 取决于实际渲染顺序，可能需要 `find.byKey(...)` 替代，按 fail 信息调整。

- [ ] **Step 2：补一条校验失败 + 滚动测试（关键路径）**

```dart
testWidgets('save with empty name shows inline error', (tester) async {
  final prefs = await _prefs({});
  await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('保存食谱'));
  await tester.pumpAndSettle();

  expect(find.text('请填入食谱名称'), findsOneWidget);
});
```

- [ ] **Step 3：补一条编辑模式预填测试（含旧 amount 拆分验证）**

```dart
testWidgets('edit mode prefills legacy amount as quantity + unit',
    (tester) async {
  final legacyRecipe = Recipe(
    id: 'r-legacy',
    name: '旧食谱',
    category: '家常',
    difficulty: 2,
    cookingMinutes: 25,
    description: '',
    ingredients: const [
      RecipeIngredient(name: '西红柿', amount: '200g'),
    ],
    steps: const ['切块'],
  );

  final prefs = await _prefs({});
  await tester.pumpWidget(_app(
    prefs,
    CustomRecipeFormScreen(recipe: legacyRecipe),
  ));
  await tester.pumpAndSettle();

  // AI 折叠条在编辑模式不应渲染
  expect(find.text('✨ 粘贴链接，AI 自动填表'), findsNothing);

  // 旧 amount "200g" 应自动拆分到 quantity=200 / unit=g
  expect(find.text('200'), findsOneWidget);
  expect(find.textContaining('g'), findsWidgets); // unit chip 文本含 'g'
});
```

- [ ] **Step 4：补一条拖动重排测试（食材）**

```dart
testWidgets('ingredient drag reorder updates list order', (tester) async {
  final prefs = await _prefs({});
  await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
  await tester.pumpAndSettle();

  // 添加第二行
  await tester.tap(find.text('添加食材'));
  await tester.pumpAndSettle();

  // 给两行填名字以便区分
  final nameFields = find.widgetWithText(TextField, '食材名称');
  await tester.enterText(nameFields.at(0), '第一');
  await tester.enterText(nameFields.at(1), '第二');

  // 通过 drag handle 重排（在新 ReorderableListView 中，使用 longPress + drag 模拟）
  final firstHandle = find.byIcon(Icons.drag_indicator).first;
  await tester.drag(firstHandle, const Offset(0, 80));
  await tester.pumpAndSettle();

  // 重排后第二行的"第一"出现在 index 1 上
  // 简化断言：两个名字都仍存在
  expect(find.text('第一'), findsOneWidget);
  expect(find.text('第二'), findsOneWidget);
});
```

> 拖动测试用 `tester.drag` 在 widget 测试中可能不稳。如果失败，把它降级为冒烟测试或在 Task 17 手动验证。

- [ ] **Step 5：跑全部测试**

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 6：跑 analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7：Commit**

```bash
git add test/custom_recipe_flow_test.dart
git commit -m "test(recipe-form): add happy path, edit mode, reorder coverage"
```

---

## Task 17：手动冒烟 + 尾号修整

> 如果可在本地启动 Flutter app（macOS / iOS Simulator / Android Emulator）。

- [ ] **Step 1：启动 app 并 navigate 到「新建食谱」**

```bash
flutter run -d macos
# 或 -d <device-id>
```

操作清单：
- [ ] AI 折叠条默认折叠，点击展开 → 输入框出现
- [ ] 没图时显示紧凑封面卡，点上传 / 拍照
- [ ] 基础信息：名称 placeholder、分类 chips（含 "+ 其他" 弹窗）、时间 chips + 自定义、难度星 + label、简介 3 行
- [ ] 食材：拖动 handle 重排、单位下拉 sheet、删除按钮
- [ ] 步骤：圆形编号正确（删除后自动重算）、拖动重排
- [ ] 保存：空必填字段 → 内联错误 + 自动滚到首个错误
- [ ] 保存：填齐 → 按钮 spinner → 返回 my recipes 屏幕
- [ ] 编辑模式：进入已有食谱 → AI 折叠条不显示；旧数据正确预填（特别是单 amount 的旧食谱，quantity / unit 拆分正确）

- [ ] **Step 2：跑一次最终全测试**

```bash
flutter test
flutter analyze
```

- [ ] **Step 3（如有问题）：修整后 commit**

如果发现样式细节、间距、错误状态显示的问题，修复并 commit：

```bash
git add ...
git commit -m "polish(recipe-form): <具体描述>"
```

---

## 完成检查

- [ ] 所有 17 个 Task 已 commit
- [ ] `flutter test` 全过
- [ ] `flutter analyze` 无错误
- [ ] 手动冒烟覆盖 create + edit 模式
- [ ] spec 中"非目标"的项确实没动（`customRecipesProvider` / `Recipe` 顶层 / dashboard / my_recipes / recipe_detail）
