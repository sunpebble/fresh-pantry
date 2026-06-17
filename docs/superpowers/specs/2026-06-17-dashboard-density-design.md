# 首页信息密度重构 — 仪表盘密集网格

日期：2026-06-17 · 范围：`apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift`（纯展示层重构）

## 目标

把首页从「单列全宽卡片纵向堆叠」改为「仪表盘式密集网格」，在不丢任何现有信息与交互的前提下显著提高单屏信息密度、减少滚动。用户已选定「激进的仪表盘密集网格」方向并批准本设计。

## 现状（问题）

首页为单列 `ScrollView`，从上到下 9 个全宽区块，区块间距处处 `xl(20)`，每张 `FkCard` 留白偏大：

1. HeroSummary（问候 + 56pt 大数字「件食材」+ 3 个大 MiniStat 瓦片）— 约占 180pt
2. 今日推荐（全宽 RecipeCard）
3. 食材分类（4 列网格，独立 section）
4. 临期提醒（逐条 FkCard + 「查看全部」）
5. 用临期 fallback 卡（ExpiringFallbackCard）
6. 膳食计划（整行入口）
7. 减废统计（整行入口）
8. 库存不足（带预览 + 全部加购的卡）
9. 购物清单（整行入口）

最大密度浪费：底部三个「整行只放一个统计」的入口（膳食/减废/购物）、偏高的 Hero、处处 `xl` 间距。

## 目标布局（top → bottom）

仍在现有 `ScrollView` + `NavigationStack` 内。区块间距 `xl → md(12)`；2 列瓦片用**等高 HStack**（同行高度对齐，靠各瓦片背景 `maxHeight: .infinity` 撑到较高者），列间距 `sm(8)`，左右 `lg` padding 不变。

1. **统计条 StatBar**（替代 HeroSummary）：紧凑卡。第一行小问候「早安，主厨」（保留，单行，`fkTitleMedium`）；第二行横向统计段：`N 件 · M 类 · ⚠K 需处理 · ⛔E 过期 · ✓F 充足`，沿用 warn/danger/success 配色。高度约现 Hero 的 1/3。
2. **今日推荐**：不变 — 全宽 `RecipeCard` + 首次加载 `RecipeSkeletonCard`。
3. **用临期 · 今天就能做**：保留但瘦身为单行全宽强调条（🔥 + 菜名 + 「可用 N 件临期」+ chevron），仅当 `fallback != nil` 时出现，点按 push 菜谱详情。
4. **富瓦片行（等高 HStack）**：
   - 临期提醒(N)：前 2 条临期（名称 + 剩余天数 + 紧凑 `cart.badge.plus` 加购按钮）+「查看全部 →」底栏（push `ExpiringView`）。空态「暂无临期 ✓」。
   - 食材分类：5 大类的 2 列 mini 网格（分类图标 + 件数），每格可点 → `onSelectCategory`（下钻库存对应分类）。
5. **统计瓦片行 1（等高 HStack）**：膳食计划（📅 未来 7 天 N 顿 +「还缺 K 样」badge，push `MealPlanView`）｜ 减废统计（🌿 本月用掉率 X% +「抢救 N」badge，push `WasteInsightsView`）。
6. **统计瓦片行 2（等高 HStack）**：购物清单（🛒 N 项待购 / 已完成 → 切 购物 tab）｜ 库存不足（🛍 N 项常买缺货 → push `LowStockView`）。

## 决策

- **A — 保留小问候**：StatBar 第一行保留「早安，主厨」时段问候（沿用 `HeroSummary.greeting`）。
- **B — 库存不足降级**：放弃首页内联「全部加入购物清单」一键 + 预览列表；降级为小瓦片，点进 `LowStockView`（该页已有底部「加入购物清单 (N)」批量 CTA + 逐项选择，能力不丢）。随之删除 `LowStockInlineCard`、`addAllLowStock`、`showLowStockConfirm`、`isAddingLowStock`、`confirmationDialog`。

## 必须保留的行为（回归清单）

- 全部导航路由：`DashboardRoute.{expiring,mealPlan,wasteInsights,lowStock}`、`selectedRecipe` 详情 push、`onSelectShopping`/`onSelectCategory`/`onSearch`/`onSelectExpiringRecipes`。
- 逐项 `cart.badge.plus` 加购（`addToShopping`）+ 乐观购物计数（`store.noteShoppingAdded`）+ toast 三态（added/duplicate/failed）。
- 分类瓦片下钻、`-initialRoute` 启动钩子、通知 tap → push 临期、widget 深链 → push 路由。
- 家庭切换 scope 守卫：`.task(id: householdID)` 的 load-then-assign、`secondaryScope` 重建 lazy store、每个 await 后的 scope/cancel 重检。
- 远端合并脉冲 `onChange(dataRevision)` 重载主 store + secondary stats。
- reduce-motion 入场（`fkEntrance`）、a11y 标签/标识、下拉刷新、搜索 toolbar。

## 新增逻辑与测试策略

落地时确认：本次重构**无新增领域逻辑**——StatBar、临期瓦片、分类瓦片、统计瓦片读的全是已被 `DashboardStoreTests` / `MealPlanGlanceTests` 覆盖的字段（`DashboardSummary.{totalItems,needsAttentionCount,expiredCount,freshCount,uncheckedShoppingCount,expiringPreview}`、`categoryCounts`、`MealPlanGlance`、`FoodLogStats`）。

因此**放弃原计划的 `DashboardSummary.statSegments` helper**（纯展示，会是冗余测试面）。这是一次纯展示层重排，验证靠「编译通过 + 既有 1280+ 测试全绿 + 模拟器截图核对 + 保留 `home.category.<name>` 标识符不破坏 `CategoryDrillDownUITests`」。

## 落地与验证

- XcodeGen 重生工程；新增/改动测试与既有 `DashboardStoreTests` 全绿；Release 编译过。
- 模拟器截图核对密度与各瓦片。
- ultracode 工作流编排：理解（行为/复用/测试清单）→ 实现（inline TDD）→ 对抗评审（行为保真 / SwiftUI 等高布局 / a11y+reduce-motion+Dynamic Type / 测试编译）。

## 非目标

- 不改 `DashboardStore` 的数据口径与同步逻辑（仅可加纯派生 helper）。
- 不动其它 tab、`ExpiringView`/`MealPlanView`/`WasteInsightsView`/`LowStockView` 内部。
- 不引入新依赖、不改设计 token。
