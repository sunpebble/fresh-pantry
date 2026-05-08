# 新建 / 编辑食谱页面 UI 重构 — 设计 spec

**日期**：2026-05-09
**作者**：kunish + Claude（brainstorming session）
**状态**：待审核
**范围**：`CustomRecipeFormScreen` 全面重构（结构 + 控件 + 反馈）

> 本 spec 对应 `2026-05-08-ai-recipe-ingredient-import-design.md` 中预留的 **SP2（字段 / 控件重做）**，但因 brainstorming 中确认范围扩大到"全面重构"，覆盖范围 ≥ 原 SP2。

---

## 1. 背景

`lib/screens/custom_recipe_form_screen.dart`（829 行）是新建 / 编辑食谱共用的表单页。SP0 + SP1 完成后，AI 一键导入 + 剪贴板检测已上线，但页面主体仍是裸 `TextField` 组合：

- 章节是 `titleLarge` 文字标题，没有视觉容器
- 分类 / 烹饪时间 / 难度都是 `TextField`（难度还要在数字键盘里敲 1-5）
- 食材的 `amount` 是单一 String，单位需要手打
- 步骤编号只在 input label 里，长食谱难定位
- 列表无法拖动重排
- 验证缺字段时弹 SnackBar 列字段名，无法定位错误位置
- 保存按钮 loading 时只是变灰，没有 spinner

## 2. 目标

- 整体观感升级到与 `lib/screens/dashboard_screen.dart` / `add_ingredient_screen.dart` 同档次的卡片化布局
- 关键字段控件升级（chips / 星级 / 拖动），减少手打和模式切换
- 食材数据形状从单 `amount` 拆为 `quantity + unit`，为 SP3（库存联动）铺路
- 验证从 SnackBar 升级为内联错误 + 滚动定位
- 保留所有现有数据 / provider 接口 / AI 导入逻辑，做到向后兼容

## 3. 非目标

- 不改 `customRecipesProvider`（add / update / remove 接口不变）
- 不改 `Recipe` 顶层字段（仅扩展 `RecipeIngredient`）
- 不实现库存联动 / 缺料加购（SP3）
- 不实现批量粘贴步骤、每步配图、AI 拆解食材（SP1 已有食材入口）
- 不引入新依赖（沿用 `flutter_riverpod` / `image_picker` / `google_fonts`）

## 4. 整体页面结构

> 单页 scroll，章节是独立 `surfaceContainerLowest` 卡片，背景仍是 `surface`。所有视觉值用 `AppSpacing` / `AppRadius` / `AppColors` / `AppTypography` token。

```
┌──────────────────────────────────────────┐
│ AppBar  ←  新建食谱                     │
├──────────────────────────────────────────┤
│ ✨ AI 折叠条  [展开]                    │  ← _isEditing=false 才渲染
│ ┌──────────────────────────────────┐   │
│ │  封面图（自适应）                 │   │  ← 无图: 紧凑卡 / 有图: 16:9 hero
│ └──────────────────────────────────┘   │
│ ╔ 📋 基础信息 ════════════╗             │
│ ║ 名称                    ║             │
│ ║ 分类 chips              ║             │
│ ║ 时间 chips + 自定义     ║             │
│ ║ 难度 ★★★★★             ║             │
│ ║ 简介                    ║             │
│ ╚═════════════════════════╝             │
│ ╔ 🥬 食材  3 项 ═══════════╗            │
│ ║ ≡ 名称   数量  单位 ⊖   ║            │
│ ║ + 添加食材              ║            │
│ ╚═════════════════════════╝            │
│ ╔ 👩‍🍳 步骤  2 步 ═════════╗            │
│ ║ ① textarea       ≡ ⊖    ║            │
│ ║ + 添加步骤              ║            │
│ ╚═════════════════════════╝            │
│ ───────────────                         │
│ [ 保存食谱 ]   ← bottomNavigationBar    │
└──────────────────────────────────────────┘
```

### 4.1 设计 token 用法

- 页面背景：`AppColors.surface`
- 卡片：`AppColors.surfaceContainerLowest` + `Border.outlineVariant` + `AppRadius.lg`
- 卡片内边距：`AppSpacing.lg`
- 卡片间距：`AppSpacing.md`（垂直）
- 章节 icon 圆角方框：28px × 28px，`AppRadius.sm` 或 `AppRadius.md`
- 文本：标题 `titleMedium` w800（与现有 dashboard 一致）；label `labelMedium`；body `bodyMedium`

## 5. 数据模型变更

### 5.1 `RecipeIngredient` 扩展

```dart
class RecipeIngredient {
  final String name;
  final String quantity;  // 新增 - 用户输入的纯数字 / 文字（"200" / "适量"）
  final String unit;      // 新增 - 单位 chip 选中值（"g" / "个" / "" 表示无）
  final String amount;    // 保留 - 兼容字段，由 quantity + unit 拼合，或从旧 JSON 直读

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
    return '$q$u'; // "200g" / "3 个"（数字 + 单位之间无空格，与现有显示一致）
  }
}
```

### 5.2 JSON 兼容性

- **写**：`toJson` 同时输出 `quantity` / `unit` / `amount`（冗余）。`amount` 仍是用户从旧版本能读到的字段。
- **读**：`fromJson` 优先读 `quantity` / `unit`；如果缺失（旧数据），用正则 `^(\d+(?:\.\d+)?)\s*(.*)$` 解析 `amount` 拆出数量和剩余文本作为 unit。无法解析时（"适量"），`quantity = ''`、`unit = amount`。

```dart
factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
  final amount = json['amount'] as String? ?? '';
  final quantity = json['quantity'] as String?;
  final unit = json['unit'] as String?;
  if (quantity != null || unit != null) {
    return RecipeIngredient(
      name: json['name'] as String? ?? '',
      quantity: quantity ?? '',
      unit: unit ?? '',
      amount: amount,
    );
  }
  final parsed = _parseLegacyAmount(amount);
  return RecipeIngredient(
    name: json['name'] as String? ?? '',
    quantity: parsed.quantity,
    unit: parsed.unit,
    amount: amount,
  );
}
```

### 5.3 单位枚举

`presetUnits`（与 `presetCategories` 同放 `lib/data/recipe_presets.dart`）：

```dart
const presetUnits = [
  'g', 'ml', 'kg', '个', '把', '根', '颗', '片', '杯', '勺', '适量',
];
```

bottom sheet 列出 preset，末尾"自定义…"打开 dialog，允许任意自定义值。

### 5.4 分类 + 时间预设

```dart
const presetCategories = ['家常', '川菜', '粤菜', '西式', '烘焙', '汤羹'];
const presetCookingMinutes = [15, 30, 45, 60, 90, 120];
```

存放在 `lib/data/recipe_presets.dart`（新文件）。

> 这些预设值列表后续可能由用户在设置页自定义；本 spec 用静态常量。

## 6. 组件拆分

> 每个 `_xxx` 是 `custom_recipe_form_screen.dart` 内的私有 widget；公共可复用部分提到 `lib/widgets/recipe_form/`。

### 6.1 `_AiCollapsibleBanner`（取代现有 `_AiUrlBanner`）

- 默认折叠态：`Material` 卡片样 `f0fdf4` 背景 + `b1f0ce` 描边 + 单行文字「✨ 粘贴链接，AI 自动填表」+ 右侧"展开"pill
- 点击 → `AnimatedSize` 展开为现有 `_AiUrlBanner` 内容（URL TextField + "解析为草稿" 按钮）
- 剪贴板检测命中（`_maybeOfferClipboardUrl`）时自动展开（保留 SnackBar 入口作为 backup）
- `_isEditing == true` 不渲染整个 banner

### 6.2 封面图自适应

- `_CoverImagePlaceholder`（新增）：无图态紧凑卡（120-140px 高），中央 `Icons.add_a_photo` + 「添加封面（可选）」+ 上传 / 拍照 outlined 按钮
- `_CoverImageHero`（沿用现有）：有图态保持 16:9 + 渐变 + 顶层按钮
- `CustomRecipeFormScreen.build` 根据 `_coverImageSource == null` 切换

### 6.3 `_BasicInfoCard`

包含 5 个字段，每个字段挂 `GlobalKey`（用于错误滚动定位）。

#### 6.3.1 名称
- 普通 TextField，placeholder「例如：西红柿炒蛋」
- 错误状态：`InputDecoration.errorText`

#### 6.3.2 分类 chips（复用 `lib/widgets/common/category_chips.dart`）
- 直接复用已有 `CategoryChips` widget（inventory 屏已在用，有 test 覆盖）
- 包一层薄 wrapper `_RecipeCategoryChips`：
  - 把 `presetCategories + ['+ 其他']` 作为 `categories` 参数传入；如果当前 `_categoryController.text` 不在 preset 中（例如编辑模式或之前自定义过），把这个值插入到 preset 列表里（在 "+ 其他" 之前）
  - `selectedCategory` = `_categoryController.text`
  - `onSelected`: 若选中 "+ 其他"，弹 `AlertDialog` 输入自定义值并写回 `_categoryController`；否则直接写回
- 字段值仍是 String，model 不变

#### 6.3.3 `_CookingTimeRow`
- chips 用 `lib/widgets/shared/pill_chip.dart` 中的 `PillChip` 作为构件（`selected` + `onTap` 已支持）
- 渲染 `presetCookingMinutes`（值 = `[15, 30, 45, 60, 90, 120]`）
- chip 标签：前 5 个直接显示数字（"15" / "30" / ...），最后一个 chip 标签是 "120+"（提示用户可在自定义框输入更长时间），点击该 chip 仍写入值 120，长于 120 分钟需手动在自定义框输入
- chip 点击：写入 `_cookingMinutesController.text = value.toString()`
- 下方一行：「或自定义」+ 数字 TextField（保留现有 `digitsOnly` 格式）+ "分钟" 后缀文字
- 数字 TextField onChange 时：若值精确匹配 preset 之一，对应 chip 高亮；否则全部 chip 不高亮

#### 6.3.4 `_DifficultyStars`
- `Row(children: 5 个 GestureDetector + Icon(Icons.star))`
- 1-5 颗 `AppColors.secondaryContainer`（暖橙）填充星 + 灰星
- 右侧 `Container` 显示 `_difficultyLabel(difficulty)`：1=简单 / 2=较易 / 3=普通 / 4=进阶 / 5=专业
- 字段值仍是 `int 1-5`（写回 `_difficultyController.text = difficulty.toString()`）

#### 6.3.5 简介
- TextField，maxLines: 3, placeholder「简单描述这道菜的特色…」

### 6.4 `_IngredientsCard`

- 头部：emoji icon + 「食材」标题 + 右侧 `_count` chip "N 项"
- 列表：`ReorderableListView.builder` 嵌入（`shrinkWrap: true`, `physics: NeverScrollableScrollPhysics()`，外层为 `SingleChildScrollView`）
- 每行 `_IngredientRow`：

```
┌─┬───────────┬──────┬──────┬─┐
│≡│ 食材名称  │ 数量 │ 单位▾│⊖│
└─┴───────────┴──────┴──────┴─┘
```

- 拖动 handle：`ReorderableDragStartListener` 包住 `Icons.drag_handle`
- 名称：`TextField`，wider
- 数量：`TextField`，宽 56px，`textAlign: TextAlign.right`，`keyboardType: number`，允许小数
- 单位：用 `PillChip(label: '$unit ▾', onTap: ...)` 作为触发器，点击打开 bottom sheet 显示 `presetUnits` 单选列表 + 末尾"自定义…"
- 删除：第 1 行不显示删除按钮（与现状一致）；其他行 `IconButton(Icons.remove_circle_outline)`
- 末尾「+ 添加食材」outlined dashed 按钮

### 6.5 `_StepsCard`

- 头部同食材卡（绿色 icon + 「步骤」+ count "N 步"）
- 列表：同样 `ReorderableListView.builder`
- 每行 `_StepCard`：

```
┌──┬────────────────────┬──┐
│①│ multi-line text    │≡ │
│   │ area               │⊖ │
└──┴────────────────────┴──┘
```

- 编号：32px 圆形，`AppColors.primary` 背景，`onPrimary` 文字，序号自动从 index+1
- textarea：`TextField`，maxLines: null（自动伸缩），placeholder「输入下一步…」
- 右侧 `Column(拖动, 删除)`，间隔 `AppSpacing.sm`
- 末尾「+ 添加步骤」按钮

### 6.6 `_SaveSection`（取代现有 bottomNavigationBar）

- `Column(Divider 1px, FilledButton)` 包在 `SafeArea(minimum: AppSpacing.lg)`
- 按钮 child：`_isSaving ? Row([CircularProgressIndicator(strokeWidth: 2), SizedBox(width: sm), Text('保存中…')]) : Text('保存食谱')`
- 按钮始终 enabled（除 `_isSaving`），点击时校验

## 7. 验证策略（替换 SnackBar）

### 7.1 错误状态

每个必填字段在 state 中维护 `String? _xxxError`：

```dart
String? _nameError;
String? _categoryError;
String? _cookingMinutesError;
String? _difficultyError;
String? _ingredientsError; // 整个 ingredients 列表的"至少一种食材 / 缺名称 / 缺数量"
String? _stepsError;       // "至少一个步骤"
```

### 7.2 校验流程

`_saveRecipe` 开始时：

1. 调用现有 `_missingFields(...)` 拿到错误列表（保留逻辑）
2. 把错误反向 map 到具体字段的 `_xxxError`，调用 `setState(() { ... })`
3. 如果有错误：
   - 找到第一个有 GlobalKey 的错误字段
   - `Scrollable.ensureVisible(key.currentContext!, duration: 200ms)`
   - `key.currentContext` 上 `FocusScope` 拿到第一个 `FocusNode` 并 `requestFocus()`
4. 没有错误：执行现有保存逻辑

### 7.3 错误清除

- `TextField.onChanged` / chip 选中 / star 点击：把对应 `_xxxError` 设为 `null`，无需 setState（onChange 自带 setState）
- 食材 / 步骤的错误：在 add / remove / 任一行 onChanged 时清

### 7.4 错误展示

- TextField：`InputDecoration.errorText: _xxxError`
- 非 TextField 控件（chips / stars）：在控件下方添加 `Text(_xxxError!, style: bodySmall.copyWith(color: error))`
- ingredients / steps 卡片错误：卡片头部下方一行红色 `Text` + 卡片边框红色

### 7.5 SnackBar 仍保留

- 网络/解析错误 (`_showError('保存失败，请重试')` / `_showError('请选择有效图片')`) 仍走 `showAppSnackBar`
- 只有"必填字段缺失"换成内联错误

## 8. 文件改动清单

### 新增文件

| 文件 | 用途 |
|---|---|
| `lib/data/recipe_presets.dart` | `presetCategories` / `presetCookingMinutes` / `presetUnits` 常量 |
| `lib/widgets/recipe_form/recipe_category_chips.dart` | 薄 wrapper：复用 `CategoryChips` + 处理 "+ 其他" 自定义对话框 |
| `lib/widgets/recipe_form/cooking_time_row.dart` | 时间 chips（基于 `PillChip`）+ 数字输入联动 |
| `lib/widgets/recipe_form/difficulty_stars.dart` | 5 星 + 文字标签 |
| `lib/widgets/recipe_form/unit_dropdown.dart` | 单位 chip 触发器（基于 `PillChip`）+ bottom sheet |
| `lib/widgets/recipe_form/recipe_form_card.dart` | 共享章节卡片外壳（icon + 标题 + count chip + 子内容） |
| `lib/widgets/recipe_form/ai_collapsible_banner.dart` | AI 入口折叠条（封装现有 _AiUrlBanner 内容） |

### 修改文件

| 文件 | 改动 |
|---|---|
| `lib/models/recipe.dart` | `RecipeIngredient` 添加 quantity / unit；fromJson / toJson 兼容；新增 `_parseLegacyAmount` |
| `lib/screens/custom_recipe_form_screen.dart` | 重构整个 build；引入 6.x 提到的子组件；替换 `_AiUrlBanner` 为 `_AiCollapsibleBanner`；保留 `_CoverImageHero` 并新增 `_CoverImagePlaceholder` |

### 复用（不修改）

- `lib/widgets/common/category_chips.dart`（CategoryChips）
- `lib/widgets/shared/pill_chip.dart`（PillChip）
- `lib/widgets/shared/recipe_image.dart`（RecipeImage）
- `lib/utils/app_snackbar.dart`（showAppSnackBar）

### 不动的文件

- `lib/providers/custom_recipe_provider.dart`
- `lib/services/ai_recipe_parser.dart` / `ai_client.dart` / `share_intent_service.dart`
- `lib/screens/recipe_draft_review_screen.dart`
- 其他 screens / widgets

## 9. 实现注意

### 9.1 ReorderableListView 嵌入 SingleChildScrollView

- 使用 `ReorderableListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), buildDefaultDragHandles: false, itemBuilder: ...)`
- 每个 item 必须有唯一 `key`（用 `ValueKey(_ingredientControllers[i])` 或基于 hash）
- `onReorder: (oldIndex, newIndex) { setState(() { final item = list.removeAt(oldIndex); list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item); }); }`
- `buildDefaultDragHandles: false` 因为我们要让左侧 handle 触发拖动；用 `ReorderableDragStartListener(index: i, child: Icon(Icons.drag_handle))`

### 9.2 GlobalKey 滚动定位

```dart
final _nameKey = GlobalKey();
// ...
TextField(key: _nameKey, controller: _nameController, ...)
// 滚动:
await Scrollable.ensureVisible(
  _nameKey.currentContext!,
  duration: const Duration(milliseconds: 240),
  alignment: 0.1,
);
```

### 9.3 CategoryChips 自定义值

- 选中"+ 其他"chip → `showDialog` 弹文本输入
- 用户输入后：写到 `_categoryController.text`，并把这个值作为额外的 selected chip 渲染（在 preset 之外），下次进入页面如果是已有 recipe 的非 preset 分类，也按此渲染

### 9.4 单位下拉

- 用 `showModalBottomSheet` 而不是 `DropdownButton` —— 在 chip 视觉里 `DropdownButton` 内嵌不好看，bottom sheet 更克制
- Sheet 内是 ListView，每行一个单位文本；末尾"自定义…"打开 dialog

### 9.5 chip 选中视觉

- 分类 chips：复用 `CategoryChips`（已用 `GestureDetector + AnimatedContainer`，选中态 `AppColors.primary`）
- 时间 chips、单位 chip 触发器：用 `PillChip(selected: ..., onTap: ...)`
- 不引入 Flutter 自带 `ChoiceChip`（与项目现有 chip 视觉风格不统一）

### 9.6 难度星点击

- 星数等于点击位置的 index+1
- 重复点击同一星不取消（保持现有"必填 1-5"约束）
- onTap → `setState(() { _difficultyController.text = (i+1).toString(); _difficultyError = null; })`

## 10. 错误处理

- 保存失败：仍显示 SnackBar「保存失败，请重试」（沿用现有）
- 图片选择失败：仍显示 SnackBar（沿用）
- AI 解析失败：进 review screen 处理（沿用）
- 旧 JSON 解析单位失败：fallback `quantity=''`, `unit=amount`（不丢数据）

## 11. 测试

### 11.1 Provider / Model 层

- `RecipeIngredient.fromJson` 处理新字段 (`quantity`/`unit` 都有)
- `RecipeIngredient.fromJson` 处理旧字段 (`amount` 是 "200g"，自动拆 quantity=200, unit=g)
- `RecipeIngredient.fromJson` 处理无法解析 (`amount` 是 "适量"，quantity='', unit='适量')
- `RecipeIngredient.toJson` 同时输出三个字段
- `RecipeIngredient.amount` getter / 拼合逻辑
- 持久化 round-trip 不丢数据

### 11.2 Widget 层

- 新建模式：5 个章节按顺序渲染，AI 折叠条显示
- 编辑模式：AI 折叠条不渲染；现有数据正确预填（包括非 preset 分类、非 preset 时间、非 preset 单位）
- 必填字段空时点保存 → 字段错误 errorText 显示，自动滚动到首个错误
- 字段开始编辑 → 错误清除
- 食材拖动重排 → 列表顺序更新
- 步骤拖动重排 → 列表顺序更新且编号自动重算
- 难度星点击 → controller 更新
- 时间 chip 点击 → 数字框联动
- 时间数字框输入匹配 preset 值 → chip 联动高亮
- 分类"+ 其他" → dialog → 自定义值显示并选中
- 单位下拉打开 bottom sheet → 选中后写回
- 单位"自定义…" → dialog → 自定义值
- 保存中：按钮显示 spinner，禁用
- 封面图：无图态显示紧凑卡，有图态显示 16:9 hero

## 12. 开放问题（spec 阶段不阻塞，实现时再定）

> 这些是细节决策，列在这里方便实现时（或 spec review 时）补充。

- 是否在 `_StepsCard` 头部增加 "总计预计耗时 X 分钟" 自动求和？(本 spec 暂不做)
- 是否允许在食材行内"从库存导入"？（属于 SP3，不做）
- 步骤的 textarea 是否支持图片粘贴 / 链接预览？（不做）
- 时间 chips 末尾的 "120+" 是否独立 chip？已在 6.3.3 定稿——120+ 是第 6 个 chip 的标签，点击仍写 120；超过 120 分钟需在自定义框输入。
- difficulty stars 是否支持 0 颗（即未填）？（**否**：设计要求至少 1 颗，与现有约束一致）

## 13. 不在范围

- AI 折叠条的"自动展开动画"用 `AnimatedSize` 简单实现，不要复杂 hero / shared element
- 不引入新动画库（沿用 Flutter 内置）
- 不改 Recipe.toJson 顶层（imageUrl 等字段不变）
- 不改 dashboard / my_recipes / recipe_detail 三屏（只 form 页）
