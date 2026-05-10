# Design System Phase 0:文档化 + Theme 对齐

**Date**: 2026-05-10
**Phase**: 0 / 8(UI 统一项目分解)
**Status**: Draft — 等待 user review

---

## 1. Background

最近 6 周完成了 recipe form 的完整 redesign(card 容器 + 圆角 + chip 选择器 + drag handle + inline error)。这套设计语言在 recipe form 内部已成熟,但与项目其他 screen(dashboard / inventory / add_ingredient / shopping_list / recipe_detail / my_recipes / ai_settings 等)的视觉风格不一致。

更深层的问题:项目当前同时存在**两份相互矛盾的 design system**:

1. **主题级版本**:定义在 `lib/theme/app_theme.dart`,覆盖 cardTheme / chipTheme / inputDecorationTheme 等 Material Component theme
2. **实现级版本**:体现在 `lib/widgets/recipe_form/` 各 widget 中,通过 `Container` + 显式样式自实现,完全绕过主题

两者的具体差异(card 圆角 24 vs 16、card 底色 surfaceContainer vs surfaceContainerLowest、chip 默认色 surfaceContainerHigh vs surfaceContainerLow 等)使得"design system"在工程上不存在 — 因为没有单一权威。

本 phase 是 UI 统一项目的第一阶段,目标是先把 design system 文档化并让"两份"对齐为"一份",为后续 phase 1(共享 widget 库)和 phase 2-7(逐个 screen 改造)提供工程契约。

## 2. Scope

### 2.1 包含

- 创建 `docs/design-system.md`,覆盖 L1-L5 五层 32 条目(其中 11 条占位待后续 phase 拍板)
- 修改 `lib/theme/app_theme.dart`,使 cardTheme / chipTheme 与 recipe form 实现级版本对齐
- 修改 `lib/theme/app_typography.dart`,新增 `AppTypography.sectionTitle` 派生 token

### 2.2 不包含

| # | 不做 | 后续 phase |
|---|---|---|
| N1 | 修改 `lib/widgets/` 下任何文件 | 全部留给 phase 1+ |
| N2 | 修改 `lib/screens/` 下任何文件 | 留给 phase 2-7 |
| N3 | 抽离共享 widget(SectionCard / SelectChipRow 等) | phase 1 |
| N4 | `PillChip` 默认 `fontSize: 13` → `14` | phase 1 |
| N5 | `RecipeFormCard` 改用 cardTheme / sectionTitle | phase 1 |
| N6 | 删除 / 改动 `design/html/` 旧设计稿 | 永久不做(归档) |
| N7 | 任何 screen 视觉改造 | phase 2-7 |
| N8 | L3.9 / L4.4-4.7 / L5.1/3-6 等占位条目的实质决定 | 各自标注的后续 phase |

## 3. Goals

- 在项目里建立单一权威 design system 文档,作为后续所有 UI 改造的契约
- 消除"两份 design system 矛盾"的根本问题(让主题对齐到 recipe form 实现版)
- 为 L4 / L5 中尚未拍板的项目建立**结构化占位**,防止后续 phase 遗漏
- 显式记录 transient 不一致(3 条),让 phase 1 启动时第一件事是消化它们

## 4. Non-goals

- 不发明新的设计语言(以 recipe form 为基准,不做 redesign)
- 不修复 recipe form 自身的 token 违规(留给 phase 1 共享 widget 抽离时一并处理,以维持 phase 0 边界纯洁)
- 不为 phase 4 才需要的"Loading / SnackBar / 数字 stepper"等做提前决定(它们没有真实场景驱动)
- 不替换或改动 design tokens 本身(`AppColors` / `AppRadius` / `AppSpacing` 不动;`AppTypography` 仅新增派生 token)

## 5. Audit 结果

为评估 cardTheme / chipTheme 改动的影响面,在 `lib/` 内做了如下 grep:

- `\bCard(` → **0 处** Material Card 用法
- `Chip(` / `FilterChip(` / `ChoiceChip(` / `ActionChip(` → **0 处** Material Chip 用法

**结论**:phase 0 调整 cardTheme / chipTheme **不影响任何现有渲染**,因为整个 codebase 中没有走主题的 Card / Chip。原本评估的"风险 1 / 风险 2"基本消除。phase 0 改动 app_theme 是为 phase 1 抽出的共享 widget**预先准备主题**,而不是修改现有视觉。

**但发现两个新的自定义 chip 实现**(都不走 PillChip,也不走 chipTheme):

- `lib/widgets/common/category_chips.dart` 内的 `_CategoryChip`(用于顶部分类切换)
- `lib/widgets/shared/ai_draft_field.dart` 内的 `AiDraftFieldChip`(用于 AI draft state)

这两处加上 `PillChip`,项目里实际上有 **3 套 chip 实现**。phase 1 抽离共享 widget 时应将三者合并为一,本 spec 仅记录该事实,不在 phase 0 内处理。

## 6. 调和决定(7 条)

| # | 决定项 | 拍板结果 | 理由 |
|---|---|---|---|
| 1 | Card 圆角 | `AppRadius.lg = 16` | 跟随 recipe form 实现;高密度页面更紧凑 |
| 2 | Card 底色 | `AppColors.surfaceContainerLowest`(白) | 跟随 recipe form 实现;与 `surfaceBright` 背景有微 contrast |
| 3 | Card 边框 | 1px `outlineVariant`,error 态 1.5px `error` | 跟随 recipe form 实现;无边框白底易"消失" |
| 4 | Chip 实现 | `PillChip` 是项目唯一 chip 实现 | recipe form 已经全面 PillChip;减少多套实现 |
| 5 | Chip 默认底色 | `AppColors.surfaceContainerLow` + 文档 contrast 注 | 跟随 PillChip 默认;白底 card 上消费方主动传 `surfaceContainer` 提升对比 |
| 6 | Chip 字号 | `14`(`labelLarge`) | 文档强制 14;PillChip 默认 13 是 token 违规,留 phase 1 改 |
| 7 | Section title 字重 | 在 `app_typography.dart` 新增 `AppTypography.sectionTitle` | 给规则一个 named token,避免每个 widget 自己 `copyWith(w800)` |

## 7. 文档结构(`docs/design-system.md`)

文档约 800 行 markdown,5 大章节,32 条目(完整描述 21 + 占位 11)。

### L1 Tokens(4 条,完整)

| # | 条目 | 内容 |
|---|---|---|
| 1.1 | Color | 引用 `AppColors`;描述 surface 八级阶梯、primary 家族、error 家族、AI accent |
| 1.2 | Spacing | 引用 `AppSpacing`;每级用例(xs 紧凑 / lg 段间 / xxl 屏幕边距) |
| 1.3 | Radius | 引用 `AppRadius`;阶梯用例(sm 内嵌 / lg 卡片 / pill 圆 chip) |
| 1.4 | Typography | 引用 `AppTypography.textTheme`;新增 `sectionTitle` getter |

### L2 主题(5 条,完整,描述 phase 0 调整后的 `app_theme.dart`)

| # | 条目 | 决定 |
|---|---|---|
| 2.1 | Card | 16 圆角 / `surfaceContainerLowest` / 1px `outlineVariant` 边框 |
| 2.2 | Chip | `PillChip` 唯一;`chipTheme` 作 fallback 与 PillChip 默认对齐 |
| 2.3 | InputDecoration | filled / 16 圆角 / 无边框 / focus 时 primary 1.5px |
| 2.4 | Button | `FilledButton` stadium / 24-16 内边距;`TextButton` stadium |
| 2.5 | AppBar / Scaffold | scaffold 底 `surface`;AppBar 透明 + `scrolledUnderElevation: 0` |

### L3 组件 patterns(10 条,以 use case 为主,9 完整 + 1 占位)

| # | Pattern | 参考实现 | 状态 |
|---|---|---|---|
| 3.1 | 分区卡片 | `RecipeFormCard` | 完整 |
| 3.2 | 横向多选(预设) | `CookingTimeRow` + `PillChip` | 完整 |
| 3.3 | Wrap 多选(分类) | `RecipeCategoryChips` + `PillChip` | 完整 |
| 3.4 | Bottom sheet 单选 | `UnitDropdown` | 完整 |
| 3.5 | 可拖动列表 | `custom_recipe_form_screen` ingredients/steps section | 完整 |
| 3.6 | 内联校验(字段级 + 卡片级) | `RecipeFormCard.hasError` + 字段 `errorText` | 完整 |
| 3.7 | 可折叠 banner | `AiCollapsibleBanner` | 完整 |
| 3.8 | 难度评级 | `DifficultyStars` | 完整 |
| 3.9 | 数字 stepper | 暂无参考实现 | **占位**,phase 4 add_ingredient 拍板 |
| 3.10 | 图标 chip | `PillChip` + `icon` 参数 | 完整 |

### L4 页面级 patterns(7 条,3 完整 + 4 占位)

| # | 条目 | 状态 |
|---|---|---|
| 4.1 | Scaffold + SafeArea(`app.dart` 顶层) | 完整 |
| 4.2 | TopAppBar(主 4 screen)/ Material AppBar(次级 screen) | 完整 |
| 4.3 | BottomNavBar + IndexedStack 切换 | 完整 |
| 4.4 | 水平 padding | **占位**,phase 2 dashboard 拍板 |
| 4.5 | 垂直 section 间距 | **占位**,phase 2 dashboard 拍板 |
| 4.6 | Section header(分组标题) | **占位**,phase 2 dashboard 拍板 |
| 4.7 | FAB / 中央 + 按钮 | **占位**,inventory / shopping 落地时拍板 |

### L5 交互模式(6 条,1 完整 + 5 占位)

| # | 条目 | 状态 |
|---|---|---|
| 5.1 | SnackBar | **占位**,首次落地的 phase 拍板 |
| 5.2 | Inline error | 完整(同 L3.6) |
| 5.3 | Loading | **占位**,phase 4 add_ingredient 拍板 |
| 5.4 | Empty state | **占位** |
| 5.5 | 确认弹窗 | **占位**,参考 `RecipeCategoryChips` 自定义分类 |
| 5.6 | Bottom sheet | **占位**(L3.4 已部分覆盖) |

### 文档自身结构

每个完整条目约 15-30 行 markdown,包含:

1. **标题 + 一句话定义**
2. **token / 主题引用**(指向 dart 文件路径)
3. **参考实现路径**(精确到 widget 类名)
4. **使用约束**(何时用 / 何时不用)
5. **反例 / 边界条件**(可选)

每个占位条目约 5 行,包含:

1. **标题 + 状态**(占位)
2. **将由哪个 phase 拍板**
3. **拍板时需考虑的输入**(可选)

文档前置 / 后置:

- 文档第一段:说明 source of truth、`design/html/` 已过时但保留归档
- 文档末附录:`Transient 不一致清单`(3 条)+ `决策记录`(7 条调和决定的取舍理由)

## 8. 代码改动

### 8.1 `lib/theme/app_theme.dart`

```dart
// before
cardTheme: CardThemeData(
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  color: AppColors.surfaceContainer,
  margin: EdgeInsets.zero,
),

// after
cardTheme: CardThemeData(
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.lg),
    side: const BorderSide(color: AppColors.outlineVariant),
  ),
  color: AppColors.surfaceContainerLowest,
  margin: EdgeInsets.zero,
),
```

```dart
// before
chipTheme: ChipThemeData(
  shape: const StadiumBorder(),
  backgroundColor: AppColors.surfaceContainerHigh,
  selectedColor: AppColors.primary,
  labelStyle: AppTypography.textTheme.labelLarge,
  showCheckmark: false,
  side: BorderSide.none,
),

// after
chipTheme: ChipThemeData(
  shape: const StadiumBorder(),
  backgroundColor: AppColors.surfaceContainerLow,  // High → Low
  selectedColor: AppColors.primary,
  labelStyle: AppTypography.textTheme.labelLarge,
  showCheckmark: false,
  side: BorderSide.none,
),
```

其余 theme(InputDecoration / FilledButton / TextButton / AppBar / `kAppSystemOverlayStyle` / Scaffold backgroundColor)**保持不变**。

### 8.2 `lib/theme/app_typography.dart`

```dart
class AppTypography {
  // 现有 textTheme getter 不动

  /// Section card 标题样式:`titleMedium` 提到 w800。
  /// 用于 SectionCard / RecipeFormCard 等"分区标题"场景。
  static TextStyle get sectionTitle =>
      textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800);
}
```

## 9. Transient 不一致清单

phase 0 完成后,以下 3 条不一致**仍然存在**,文档明确标记为 phase 1 跟进:

| # | 不一致 | 文件 | phase 1 处理 |
|---|---|---|---|
| T1 | `PillChip` 默认 `fontSize: 13` 与文档规定的 14(labelLarge)不符 | `lib/widgets/shared/pill_chip.dart` | 改默认值,或参数化时使用 `labelLarge` |
| T2 | `RecipeFormCard` 用 `Container` 自实现卡片,不走 cardTheme | `lib/widgets/recipe_form/recipe_form_card.dart` | 抽 `SectionCard` 共享 widget,改用 `Card` + `cardTheme` |
| T3 | `RecipeFormCard` 标题 `fontWeight: FontWeight.w800` 硬编码 | 同 T2 | 改用 `AppTypography.sectionTitle` |

此外,审计期间发现的两个 chip 实现(不在 phase 0 拍板范围,但记入 phase 1 工作内容):

- `_CategoryChip`(`lib/widgets/common/category_chips.dart`)→ phase 1 合并到 `PillChip`
- `AiDraftFieldChip`(`lib/widgets/shared/ai_draft_field.dart`)→ phase 1 合并到 `PillChip`(可能需要 `PillChip` 暴露更多参数)

## 10. 验收标准 (Definition of Done)

### 产出物

| # | 产出物 | 路径 | 验证 |
|---|---|---|---|
| D1 | Design System 文档 | `docs/design-system.md` | 文件存在,覆盖 L1-L5 全部 32 条目(完整 21 + 占位 11) |
| D2 | Phase 0 自身 spec | `docs/superpowers/specs/2026-05-10-design-system-phase0-design.md` | 已写并 commit |
| D3 | `app_theme.dart` 对齐 | `lib/theme/app_theme.dart` | cardTheme / chipTheme 与 §8.1 完全一致 |
| D4 | typography 派生 | `lib/theme/app_typography.dart` | 新增 `AppTypography.sectionTitle` getter |

### 质量门

| # | 检查 | 命令 / 方法 |
|---|---|---|
| Q1 | 静态分析无 regression | `flutter analyze` 通过(允许已有 info 不变) |
| Q2 | 测试无 regression | `flutter test` 全绿 |
| Q3 | 主 4 screen 视觉烟囱测试 | Dashboard / Inventory / Add / Shopping 各 screen 看一遍,无意外视觉变化或 layout 错乱 |
| Q4 | recipe form 视觉无变化 | recipe form 创建 + 编辑流程的 UI 与 phase 0 之前完全一致(因为 PillChip / RecipeFormCard 都不走主题) |

### 审查门

| # | 检查 | 内容 |
|---|---|---|
| R1 | 文档"Transient 不一致"段落存在 | 列出 §9 全部 3 条 + 2 个 chip 实现遗留 |
| R2 | 文档"占位"清单完整 | 列出 11 条占位,每条注明"待哪个 phase 拍板" |
| R3 | 旧 HTML 处理段落存在 | 文档第一段说明 `design/html/` 过时,以 design system 为准 |
| R4 | 文档不引用任何不存在的 widget / token | grep 文档内 widget 名,确认在代码中存在 |

## 11. 风险

| # | 风险 | 严重度 | 缓解 |
|---|---|---|---|
| Risk 1 | cardTheme 调整影响走 Material Card 的代码点 | **极低**(audit 显示 0 处用法) | Q3 视觉烟囱测试兜底 |
| Risk 2 | chipTheme 调整影响走 Material Chip 的代码点 | **极低**(audit 显示 0 处用法) | Q3 视觉烟囱测试兜底 |
| Risk 3 | `AppTypography.sectionTitle` 命名 / API 选错,phase 1 要回头改 | 中 | 命名跟随项目惯例(`AppColors.xxx` / `AppRadius.xxx` 风格);用 `static TextStyle get sectionTitle =>` 形式 |
| Risk 4 | phase 0 文档"占位"过多,后续 phase 落地时撞墙 | 中 | 每条占位明确写"由 phase X 拍板",phase X 启动时第一件事就是回填这条文档 |
| Risk 5 | phase 0 文档与 widget 代码逐渐脱节 | 中 | 每条文档末尾标"参考实现:`<file>:<class>`";phase 1+ review 时 reviewer 检查文档同步 |

## 12. 估算

| 工作项 | 估时 |
|---|---|
| spec 文档自身 | ~30 min(本文件,已完成) |
| `app_theme.dart` + `app_typography.dart` 改动 | ~15 min |
| Audit `cardTheme` / `chipTheme` 影响面 | ~30 min(已完成,见 §5) |
| `docs/design-system.md` 写作(800 行) | ~3-4 hr |
| 视觉烟囱测试 + 微调 | ~30 min |
| **合计** | **~5-6 hr** |

## 13. 后续 phases 速览(为本 phase 提供 context,不属本 phase 范围)

| Phase | sub-project | 主要输出 |
|---|---|---|
| 0(本) | Design System 文档化 + theme 对齐 | `docs/design-system.md` + `lib/theme/` 调整 |
| 1 | 共享 widget 库 + recipe form 合规化 | `SectionCard` / `SelectChipRow` / `SelectChipWrap` / etc.;recipe form 改用主题 + sectionTitle;PillChip 14px;_CategoryChip / AiDraftFieldChip 合并 |
| 2 | dashboard 重做 | 拍板 L4.4-4.6;dashboard screen 用新 design system 重写 |
| 3 | inventory 重做(含 ingredient_card / ingredient_detail) | inventory screen 改造 |
| 4 | add_ingredient 重做 | 拍板 L3.9 数字 stepper、L5.3 Loading |
| 5 | shopping_list 重做 | 拍板 L4.7 FAB |
| 6 | recipe_detail / my_recipes 重做 | 各 screen 改造 |
| 7 | draft_review / ai_settings / 全 app token 合规化扫尾 | 收尾 |

## Appendix A:旧 HTML 设计稿处理

`design/html/*.html` 与 `design/screenshots/*.png` 是 2026-04-27 加入的早期外部设计稿,覆盖 dashboard / inventory / add_ingredient / shopping_list(含 search 状态),不覆盖 recipe form 等。

经决议,recipe form 的实现级版本(2026-05-09 redesign)成为新 source of truth,旧 HTML 稿与本 phase 拍板结果有显著视觉差异(card 边框样式、chip 字号、底色阶梯等),不再作为 source of truth。

**处理**:不删除 `design/html/` 与 `design/screenshots/`,但在 `docs/design-system.md` 第一段明确标注它们已 deprecated。这样既保留历史,也不让后续读者误读。

---

## Self-review note

本 spec 经 inline 自审,确认:

- 无 TBD / TODO / 占位文字(占位的是文档**内容**条目,标记清晰)
- §6 的 7 条决定与 §8 的代码改动 100% 一致
- §10 的 D1-D4 / Q1-Q4 / R1-R4 全部可机械验证
- §11 的 Risk 1 / 2 通过 §5 audit 已降级到极低
- §13 后续 phases 速览仅作 context,不影响本 phase 范围
- §2 的 N1-N8 与 §11 / §9 内交叉引用一致
