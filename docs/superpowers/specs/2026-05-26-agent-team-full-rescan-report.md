# Agent Team 全量重扫报告

**日期:** 2026-05-26
**Spec:** `2026-05-26-agent-team-full-rescan-design.md`
**前序报告:** `2026-05-07-agent-team-optimization-report.md`
**状态:** 阶段2完成，待用户决策

## Baseline

- `flutter analyze`: 20 issues (4 error / 6 warning / 10 info)
- `flutter test`: 333 passed / 26 failed
- 已知预存编译错误: `lib/screens/custom_recipe_form_screen.dart` onReorderItem 参数缺失，导致约 26 个测试无法编译

## Findings (合并表)

| File:Line | Severity | Category | Issue | Proposal | Risk | Source | Decision | Status |
|-----------|----------|----------|-------|----------|------|--------|----------|--------|
| lib/data/food_knowledge.dart:1 | medium | missing-test | FoodKnowledge.englishName / lookup 未单独测试。 | 新增 lookup() 命中/未命中 + englishName 单测。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/models/food_details.dart:1 | low | missing-test | FoodDetails.fromJson cacheVersion 字段处理未单测。 | 加 fromJson(cacheVersion=3) round-trip 测试。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/models/ingredient.dart:1 | low | missing-test | Ingredient.fromJson 容错(unknown storage 字符串、缺字段)未直接测试。 | 加 fromJson({'storage':'freezer'}) → fridge,缺字段使用默认。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/models/recipe.dart:1 | low | missing-test | Recipe.fromJson + ScoredRecipe.copyWith 部分字段未测。 | 补测 fromJson 缺字段 + copyWith 全字段。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/models/shopping_item.dart:1 | low | missing-test | ShoppingItem.fromJson 缺字段 / id 缺失行为未测。 | 新增 fromJson edge 单测。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/providers/ai_draft_provider.dart:66 | high | missing-error-path | 异步 run* 方法 (AiException/generic Exception) 错误处理无测试。 | 新增测试抛 AiException/AiParseException/timeout；验证 state。 | LOW | test | auto-approved | pending |
| lib/providers/deduction_review_provider.dart:1 | high | missing-test | 无 chooseCandidate/updateDeductAmount/toggleAction 的状态转换测试。 | 加参数化测试覆盖各种 mutation。 | LOW | test | blocked-by-high | pending |
| lib/providers/deduction_review_provider.dart:1 | high | missing-boundary | selectedCount 在 mixed action states / empty proposals 下未测正确性。 | 新增测试验证 selectedCount 仅统计 (selected=true AND action=deduct)。 | LOW | test | blocked-by-high | pending |
| lib/providers/deduction_review_provider.dart:11 | medium | naming | selectedCount 计算方式不一致：deduction 用 action==deduct，intake 用 status==pending。 | 统一 selection 语义。 | HIGH | quality | pending | pending |
| lib/providers/food_details_provider.dart:64 | high | sync-io-in-build | detailsFor 在 FutureProvider body 中同步 jsonDecode + jsonEncode 整张 cache。 | isolate / compute 或 LRU memoization。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/food_details_provider.dart:64 | high | missing-error-path | client.lookup 抛异常 → fallback 路径靠 try/catch swallow,未单测。 | 在 food_details_provider_test 增加 client throws 测试。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/food_details_provider.dart:45 | medium | provider-graph | foodDetailsProvider 是 family 但非 autoDispose;每次 ingredient identity 变就新建 entry。 | `FutureProvider.autoDispose.family`。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/intake_review_provider.dart:1 | high | missing-test | 无 empty→seeded→applied→cleared 状态转换测试；无 toggleSelected/toggleAction/updateProposal 测试。 | 加参数化测试覆盖各 state mutation。 | LOW | test | blocked-by-high | pending |
| lib/providers/intake_review_provider.dart:1 | high | missing-error-path | 无 _persistDraft 错误处理测试（SharedPreferences 写失败、JSON encode 异常）。 | 新增 mock SharedPreferences.setString throw 的测试。 | LOW | test | blocked-by-high | pending |
| lib/providers/intake_review_provider.dart:1 | high | missing-boundary | 无 empty proposals/null shelfLifeDays/duplicate IDs/极端 quantities 边界测试。 | 新增边界条件测试用例。 | LOW | test | blocked-by-high | pending |
| lib/providers/intake_review_provider.dart:60 | medium | duplication | applyToInventory() 模式在 intake 与 deduction notifier 间重复。 | 提取共享 mixin ReviewNotifierBase。 | HIGH | quality | pending | pending |
| lib/providers/inventory_provider.dart:143 | high | missing-error-path | _save 失败抛 StateError 未测试,_recordAddHistory 同失败路径未测。 | mock SharedPreferences setString 返回 false 触发 StateError。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/inventory_provider.dart:188 | high | missing-test | InventoryNotifier.update + remove 边界(index<0 / 越界 / state 不变)未单独测试。 | 加测 update(-1)/update(99)/remove(-1)/remove(99) 不变更。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/inventory_provider.dart:239 | medium | provider-graph | 没有 autoDispose;derived (filtered*, foodDetailsProvider.family, recipeSearchRepositoryProvider) 也无 autoDispose。 | 对 derived 加 .autoDispose;core notifier 保留 keepAlive。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/inventory_provider.dart:243 | medium | provider-graph | 用 _addHistoryVersionProvider+ref.read 触发 frequentItems 重算(绕过 Riverpod 依赖图)。 | 把 add_history 也建成 NotifierProvider。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/inventory_provider.dart:324 | medium | missing-edge-case | frequentItemsProvider 测试覆盖排序但没测 count<2 过滤 / take(6) cap。 | 加测 8 个 frequent + 1 个 count=1 验证。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/notification_sync_provider.dart:9 | high | anti-pattern | Mutable _previousIds field outside Riverpod state — race condition risk if _resync called concurrently. | Refactor to store previousIds in NotificationSyncNotifier state. | HIGH | test | pending | pending |
| lib/providers/notification_sync_provider.dart:24 | high | missing-error-path | 无 _resync 错误测试：ExpiryScheduler.compute throws / service.syncAll throws / permission denied. | 新增 mock ref.read 抛错的测试。 | LOW | test | blocked-by-high | pending |
| lib/providers/recipe_provider.dart:51 | high | missing-error-path | RecipeSearchRepository.searchByName 客户端抛异常未单独测。 | 加测 client.searchByName throws,确认外层不抛。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/recipe_provider.dart:112 | medium | provider-graph | recipesProvider FutureProvider watch inventoryProvider,每次库存变动→重算并发起多次网络请求。 | 把搜索关键词稳定化。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/recipe_provider.dart:150 | medium | provider-graph | recommendedRecipesProvider watch 三个 provider 并完整重算 score 排序。 | 用 .select(items=>names set) 缩窄依赖。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/recipe_provider.dart:188 | medium | missing-edge-case | matchedIngredientCount 当 inventory 与 recipe 都为空时未直接测试。 | 加测空 inventory + 空 recipe.ingredients = 0。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/recipe_provider.dart:17 | low | over-abstraction | `MealDbClient`/`FoodDetailsClient` 仅有一个生产实现但被多份测试 fake 实现,`TheMealDbClient` 仅是对 `TheMealDbService.searchByName` 的一行转发。 | 合并 `TheMealDbClient` 到 `TheMealDbService`,把后者改为可实例化、把抽象改名 `MealDbApi`。 | HIGH | quality,carried-from-2026-05-07 | pending | pending |
| lib/providers/reminder_settings_provider.dart:13 | medium | missing-error-path | 无 JSON 反序列化失败测试（malformed JSON / missing fields / version mismatch）。 | 新增 corrupted JSON in SharedPreferences 测试，验证 fallback。 | LOW | test | auto-approved | pending |
| lib/providers/reminder_settings_provider.dart:22 | medium | missing-boundary | 无 update() with all null params 测试；无并发 update 测试。 | 新增 update() 全 null 调用测试，验证 state 不变。 | LOW | test | auto-approved | pending |
| lib/providers/search_provider.dart:43 | high | missing-test | searchFoodDetailsProvider / SearchHistoryNotifier 几乎零覆盖。 | 新建 search_provider_test.dart 覆盖 history add/remove/clear/dedupe/cap10 + searchFoodDetails<2 字符。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/search_provider.dart:17 | medium | missing-edge-case | filteredInventoryProvider 大小写/全空格/无匹配/空 keyword 路径未单测。 | 新增针对 filteredInventoryProvider 的 unit test。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/providers/search_provider.dart:43 | medium | provider-graph | searchFoodDetailsProvider 每键入一次重新构造 Ingredient,没有 debounce。 | autoDispose + debounce。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/providers/shopping_provider.dart:116 | high | missing-test | ShoppingNotifier.remove / toggleCheck 缺单元测试。 | provider_logic_test.dart 加 remove unknown id + toggleCheck 切换持久化。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/providers/shopping_provider.dart:144 | medium | missing-edge-case | addFromSuggestion 空白/全空格输入返回 false 未测。 | 加测 addFromSuggestion('   ') 返回 false。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:289 | high | missing-loading | _save 同步执行,无 in-flight 状态;批量重复点击会创建多条。 | 加 _isSaving 标志置 disable 并显示 progress。 | LOW | ux,carried-from-2026-05-07 | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:391 | medium | rebuild | watch frequentItemsProvider 在大表单顶部,frequent 每次 add 触发整个表单 rebuild。 | 把 frequentItems 抽出成独立子 ConsumerWidget。 | LOW | perf,carried-from-2026-05-07 | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:1011 | medium | allocation-in-build | _buildFilledInput 每次 build 内嵌 Focus+Builder+AnimatedContainer+TextField,新建 BoxDecoration / Border / TextStyle。 | 抽成独立 StatelessWidget,InputDecoration / TextStyle 提为 static const。 | LOW | perf,carried-from-2026-05-07 | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:597 | low | allocation-in-build | DropdownButton items 列表每次 build 重建 List<DropdownMenuItem>。 | 缓存或 const 化。 | LOW | perf,carried-from-2026-05-07 | auto-approved | pending |
| lib/screens/custom_recipe_form_screen.dart:236 | high | missing-error | 保存失败仅 SnackBar"保存失败,请重试",无重试按钮。 | 统一错误恢复路径并提供 retry CTA。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/custom_recipe_form_screen.dart:326 | high | compile-error | ReorderableListView.builder 使用已废弃的 onReorderItem 参数 (Flutter API 变更) — 阻塞所有测试。 | 用 onReorder 回调替换 onReorderItem。 | LOW | test | blocked-by-high | pending |
| lib/screens/custom_recipe_form_screen.dart:442 | high | compile-error | 同 :326 — onReorderItem 在 line 442 也已废弃。 | 用 onReorder 替换 onReorderItem。 | LOW | test | blocked-by-high | pending |
| lib/screens/custom_recipe_form_screen.dart:157 | medium | list-builder | `for (var i=0;...)` 把 ingredient/step 行铺成 Column children;输入项极少时可接受。 | 用 ListView.builder。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:24 | high | missing-test | 553 行 dashboard 屏幕本身没有专属测试文件。 | 新增 dashboard_screen_test.dart 完整渲染 + 快捷动作 + 推荐食谱。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:29 | high | rebuild | DashboardScreen 同时 watch 6 个 provider;任一变动整屏 rebuild。 | 拆分为多个子 ConsumerWidget,各只 watch 自己的 provider。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/dashboard_screen.dart:40 | high | rebuild | Watches entire inventoryProvider、statCountsProvider、expiringItemsProvider、recommendedRecipesProvider 无 selector；任意数据变动触发 rebuild。 | 用 ref.watch(inventoryProvider.select((inv) => inv.length)) 等。 | HIGH | perf | pending | pending |
| lib/screens/dashboard_screen.dart:84 | high | missing-loading | RefreshIndicator 仅 Future.delayed 模拟刷新,无真实加载/错误反馈。 | 接入真实数据源并显示 loading/error。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/dashboard_screen.dart:99 | high | allocation-in-build | _ExpiringCard 在 ListView.separated 中创建 Container 未 const 化。 | 标 const 或抽 const factory widget。 | LOW | perf | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:186 | high | list-builder | `for (final (index, item) in expiringItems.indexed)` 把全部过期项展开成 Column,无虚拟化。 | 改用 SliverList.builder 或外层 CustomScrollView+SliverList.builder。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:302 | high | missing-empty-state | storageAreas 为空时无视觉占位。 | 增加 empty state。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:323 | high | missing-empty-state | recentItems 为空时直接渲染 0 项。 | 增加"暂无最近添加"empty state。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:436 | high | list-builder | _CategoryGrid 用 GridView.count + children 列表，未用 .builder。 | 改 GridView.builder。 | LOW | perf | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:154 | medium | long-function | "紧急关注" Container 内联约 130 行,build 方法整体超长(约 320 行)。 | 抽取 `_UrgentAttentionSection` StatelessWidget。 | LOW | quality,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:302 | medium | list-builder | `for (final (index, area) in storageAreas.indexed)` 同步展开 storage cards。 | 用 ListView.builder 或 SliverList.builder。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/dashboard_screen.dart:393 | low | long-function | `_showRecipeSheet` 87 行 build 一个 modal sheet。 | 抽 `_RecipeRecommendationSheet` 私有 widget。 | LOW | quality,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/deduction_review_screen.dart:52 | high | missing-loading | 异步 applyToInventory() 无 loading 指示或进度反馈。 | 包 loading overlay；实现 loading state UI。 | LOW | ux | auto-approved | pending |
| lib/screens/deduction_review_screen.dart:22 | high | theme-inconsistency | 空状态用硬编码 EdgeInsets.all(24)，未用 AppSpacing token。 | 替换为 EdgeInsets.all(AppSpacing.lg)。 | LOW | ux | auto-approved | pending |
| lib/screens/deduction_review_screen.dart:52 | medium | missing-error | applyToInventory() 抛错无 UI 处理。 | try-catch + error snackbar。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:241 | high | a11y | 食材行 GestureDetector 无 Semantics 包装。 | 包 Semantics(label: 'View ${item.name} details', button: true)。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:363 | high | a11y | _MiniBtn GestureDetector 无 Semantics 包装。 | 包 Semantics(button: true, label: label)。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:230 | high | theme-inconsistency | 硬编码 padding: EdgeInsets.all(14), EdgeInsets.symmetric(horizontal:18) 等魔术数字。 | 提取至 AppSpacing token。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:119 | high | theme-inconsistency | 直接 GoogleFonts (plusJakartaSans, manrope) 调用，未走 theme textStyles。 | 集中到 AppTheme；用 AppTypography token。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:250 | high | theme-inconsistency | 硬编码 borderRadius:12，未用 AppRadius.md token。 | 用 BorderRadius.circular(AppRadius.md) 替换。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:203 | high | allocation-in-build | Column with for 循环创建 _ExpiringRow widgets，无 const 优化。 | 提为 const list 或用 ListView.builder。 | LOW | perf | auto-approved | pending |
| lib/screens/expiring_screen.dart:230 | high | allocation-in-build | _ExpiringRow 创建多个 Container 未 const 化。 | 对嵌套 Container 用 const。 | LOW | perf | auto-approved | pending |
| lib/screens/expiring_screen.dart:30 | medium | rebuild | ref.watch(expiringItemsProvider) 整 provider 监听，无 selector。 | 用 .select() 仅监听 expired/soon 子集。 | HIGH | perf | pending | pending |
| lib/screens/expiring_screen.dart:250 | medium | responsive | 固定尺寸 width:44 height:44, width:36 height:36，无响应式缩放。 | 用 design token；考虑屏幕尺寸。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:98 | medium | allocation-in-build | _RemindShortcut 创建 Container 未 const 化。 | 对固定属性 Container 用 const。 | LOW | perf | auto-approved | pending |
| lib/screens/expiring_screen.dart:323 | medium | missing-error | _markUsed() 在 error 时静默返回，无用户反馈。 | inventory index 未找到时显示 error snackbar。 | LOW | ux | auto-approved | pending |
| lib/screens/expiring_screen.dart:334 | medium | missing-error | _addToShopping() 异步可能失败而无 error 处理 UI。 | 加 try-catch；失败 snackbar。 | LOW | ux | auto-approved | pending |
| lib/screens/ingredient_detail_screen.dart:206 | high | responsive | Container height:220 hero 图固定高。 | 改 AspectRatio(16/9) 或 LayoutBuilder。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/ingredient_detail_screen.dart:329 | high | responsive | LayoutBuilder 阈值 360 硬编码;且 SizedBox(width:184) 在中等屏可能挤占。 | 抽 breakpoint 常量。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/ingredient_detail_screen.dart:163 | medium | selector-granularity | watch 整个 inventoryProvider 仅为找当前 item 副本。 | .select((items)=>items[index])。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/intake_review_screen.dart:1 | high | duplication | Screen 结构与 deduction_review_screen.dart 几乎完全相同 (ListView, ReviewBottomBar, empty state)。 | 创建可复用 BaseReviewScreen<T> widget。 | HIGH | quality | pending | pending |
| lib/screens/intake_review_screen.dart:58 | high | missing-loading | 异步 applyToInventory() 无 loading 指示或进度反馈。 | 包 loading overlay；显示 loading SnackBar。 | LOW | ux | blocked-by-high | pending |
| lib/screens/intake_review_screen.dart:21 | high | theme-inconsistency | 空状态用硬编码 EdgeInsets.all(24)，未用 AppSpacing token。 | 替换为 EdgeInsets.all(AppSpacing.lg)。 | LOW | ux | blocked-by-high | pending |
| lib/screens/intake_review_screen.dart:58 | medium | missing-error | applyToInventory() 抛错无 UI 处理。 | try-catch + error snackbar。 | LOW | ux | blocked-by-high | pending |
| lib/screens/inventory_screen.dart:22 | high | missing-loading | _onRefresh 仅 800ms delay,无真实数据加载/错误显示。 | 集成 provider 加载状态。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/inventory_screen.dart:125 | high | selector-granularity | watch 整个 filteredByCategoryProvider,任一字段变动整屏 rebuild。 | 在 item 级用 select 或拆 family provider。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/inventory_screen.dart:140 | high | rebuild | 多个 provider 无 selector：inventoryProvider, selectedCategoryProvider, filteredByCategoryProvider, lowStockItemsProvider。 | 用 .select() 仅监听必要字段。 | HIGH | perf | pending | pending |
| lib/screens/inventory_screen.dart:146 | high | sync-io-in-build | 自由文本搜索在 build 中同步过滤 (toLowerCase + contains)。 | 创建 computed provider 或用 FutureProvider + debounce。 | HIGH | perf | pending | pending |
| lib/screens/inventory_screen.dart:470 | high | allocation-in-build | _CategoryChipRow 在 ListView.separated 中创建 Container 未 const 化。 | 标 const 或抽 const widget。 | LOW | perf | blocked-by-high | pending |
| lib/screens/my_recipes_screen.dart:23 | high | missing-empty-state | empty 文案过于简陋。 | 提供 empty illustration + 引导按钮。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/my_recipes_screen.dart:1 | medium | missing-test | 仅 custom_recipe_flow_test 触及 list 渲染。 | 加测空状态 CTA + 多食谱排序。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/my_recipes_screen.dart:55 | medium | selector-granularity | _MyRecipeCard.build 中 watch 整个 inventoryProvider 给每张卡。 | 把 matchedCount 提到顶层计算。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/recipe_detail_screen.dart:115 | high | responsive | SliverAppBar expandedHeight:240 在小屏极易遮挡内容。 | MediaQuery 适配或响应式比例。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/recipe_detail_screen.dart:148 | high | list-builder | SliverChildListDelegate 一次性铺所有 ingredients+steps;且 inventoryNames Set 在 build 内重算。 | 拆 SliverList.builder,把 inventoryNames 用 useMemoized 或外提。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/recipe_detail_screen.dart:1 | medium | missing-test | 506 行 recipe_detail_screen 仅有 custom_recipe_flow_test 间接测试。 | 加测 step toggle 持久化 + 进度展示 0/0 边界。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/recipe_detail_screen.dart:102 | medium | selector-granularity | watch 整个 inventoryProvider,但只用名字集合。 | inventoryNamesProvider 或 .select。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/recipe_detail_screen.dart:464 | medium | duplication | `_ingredientNameMatchesInventory`/`_normalizedIngredientName`/`inventoryNames = inventory.map(...)` 与 recipe_provider.dart 中辅助函数是同一算法的两份私有实现。 | 把 recipe_provider.dart 中的辅助函数改为顶层公开函数,recipe_detail_screen.dart 删本地副本。 | HIGH | quality,carried-from-2026-05-07 | pending | pending |
| lib/screens/recipe_detail_screen.dart:100 | low | long-function | `build` 方法 248 行,嵌套 SliverPadding/SliverList 内含大量 inline。 | 拆出 `_buildHeader`、`_buildMissingBanner`、`_buildIngredientsSection`、`_buildStepsSection`。 | LOW | quality,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:35 | high | rebuild | Watches inventoryProvider, recommendedRecipesProvider, recipesProvider 无 selector granularity。 | 用 .select() 提取必要子集。 | HIGH | perf | pending | pending |
| lib/screens/recipes_screen.dart:39 | high | sync-io-in-build | 复杂过滤逻辑 (expiring items check / name matching) 在 build 中同步计算，多个 where/any 链。 | 移到 computed/family provider 或 useMemoized 缓存。 | HIGH | perf | pending | pending |
| lib/screens/recipes_screen.dart:191 | high | a11y | _TabButton GestureDetector 无 Semantics 包装。 | 包 Semantics(label: '$label tab', selected: active)。 | LOW | ux | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:160 | high | theme-inconsistency | 硬编码 padding: EdgeInsets.symmetric(horizontal:18, vertical:6), EdgeInsets.fromLTRB(18,8,18,120)。 | 定义 AppSpacing token 用于 screen horizontal padding。 | LOW | ux | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:206 | high | theme-inconsistency | 直接 GoogleFonts 调用，未走 theme textStyle。 | 移到 lib/theme/app_typography.dart。 | LOW | ux | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:263 | high | theme-inconsistency | 混用 borderRadius：部分 AppRadius.pill 正确但其他硬编码 12。 | 统一到 AppRadius token。 | LOW | ux | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:262 | high | theme-inconsistency | 硬编码 Colors.white，未用 AppColors token 作为 active filter button。 | 替换为合适的 AppColors token。 | LOW | ux | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:220 | high | allocation-in-build | _TabButton 在循环上下文中创建 Container 未 const 化。 | 用 const Container 或抽 const factory。 | LOW | perf | blocked-by-high | pending |
| lib/screens/recipes_screen.dart:100 | medium | missing-loading | recipesProvider 数据加载时无 skeleton。 | 实现初始加载状态的 skeleton loader。 | LOW | ux | blocked-by-high | pending |
| lib/screens/settings_screen.dart:139 | high | rebuild | watch 4 个 provider 无 selector：inventoryProvider, shoppingProvider, reminderSettingsProvider, notificationServiceProvider。 | 用 .select() 仅监听 reminder settings + permission state。 | HIGH | perf | pending | pending |
| lib/screens/settings_screen.dart:155 | high | list-builder | ListView with children: [...] 而非 ListView.builder。 | 改 ListView.builder。 | LOW | perf | blocked-by-high | pending |
| lib/screens/settings_screen.dart:350 | high | a11y | _LinkRow GestureDetector 无 Semantics 包装；多个 interactive row 无 label。 | 包 Semantics 或用 InkWell + semanticLabel。 | LOW | ux | blocked-by-high | pending |
| lib/screens/settings_screen.dart:1 | high | theme-inconsistency | 大量硬编码 padding/margin 与魔术数字。 | 审计所有 EdgeInsets；创建/使用 AppSpacing token。 | LOW | ux | blocked-by-high | pending |
| lib/screens/settings_screen.dart:1 | high | theme-inconsistency | 大量直接 GoogleFonts 用法。 | 审计 typography；迁移到 theme-based textStyle。 | LOW | ux | blocked-by-high | pending |
| lib/screens/settings_screen.dart:594 | medium | allocation-in-build | _LinkRow 创建 Container 未 const 化。 | 标 const 或抽 const widget factory。 | LOW | perf | blocked-by-high | pending |
| lib/screens/settings_screen.dart:384 | medium | allocation-in-build | _ProfileCard 创建 Container 未 const 化。 | 对 Container 用 const。 | LOW | perf | blocked-by-high | pending |
| lib/screens/settings_screen.dart:1 | medium | theme-inconsistency | 固定 button 尺寸 (32x32, 56x56) 硬编码。 | 定义 AppSize token 用于标准尺寸。 | HIGH | ux | pending | pending |
| lib/screens/settings_screen.dart:45 | medium | missing-loading | 异步 import 操作 (backup/import) 无 loading UI。 | 显示 loading dialog。 | LOW | ux | blocked-by-high | pending |
| lib/screens/settings_screen.dart:166 | low | dead-code | _ProfileCard onTap handler 定义但未使用。 | 实现或移除 callback。 | LOW | ux | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:32 | high | rebuild | 同时 watch groupedShoppingProvider + shoppingProvider + checkedCountProvider + uncheckedCountProvider。 | 只 watch groupedShoppingProvider 派生 counts。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/screens/shopping_list_screen.dart:49 | high | rebuild | watch groupedShoppingProvider, shoppingProvider, checkedCountProvider, uncheckedCountProvider 无 selector 优化。 | 用 .select() 仅监听必要字段。 | HIGH | perf | pending | pending |
| lib/screens/shopping_list_screen.dart:48 | high | missing-loading | RefreshIndicator 假刷新。 | 接入真实加载/错误态。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/shopping_list_screen.dart:174 | high | list-builder | `SliverChildListDelegate([for (final entry in groupedItems.entries) _buildCategorySection])` 同步实例化所有分类。 | 改 SliverChildBuilderDelegate。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:204 | high | sync-io-in-build | _applyFilter() 在 build 中对 shopping list 同步过滤，每次 rebuild 都跑。 | 抽取过滤到独立 computed provider。 | HIGH | perf | pending | pending |
| lib/screens/shopping_list_screen.dart:417 | high | ui-duplication | "加入库存"逻辑与 inventory_screen 形成镜像;Ingredient 构造重复。 | 抽 IngredientFactory 或 service 方法。 | HIGH | ux,carried-from-2026-05-07 | pending | pending |
| lib/screens/shopping_list_screen.dart:584 | high | allocation-in-build | Column with for 循环创建 _ShopRow widgets，无 list builder。 | 用 ListView.builder 或抽 const-friendly 结构。 | LOW | perf | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:633 | high | allocation-in-build | Container decoration 在 build 循环中未 const 化。 | 把 BoxDecoration 提为 const static 或用 const。 | LOW | perf | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:127 | medium | list-builder | SliverChildListDelegate with list comprehension - 应用 .builder。 | 替换为 SliverChildBuilderDelegate。 | LOW | perf | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:375 | medium | list-builder | `for (final item in items)` 在每个分类内展开全部 ShoppingItemTile。 | 每分类内部也改为 ListView/SliverList.builder。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/screens/shopping_list_screen.dart:53 | low | provider-graph | 用 .listen() on provider 响应 category expansion。 | 考虑用 computed provider 表达 expansion state。 | HIGH | perf | pending | pending |
| lib/services/ai_ingredient_parser.dart:45 | medium | duplication | JSON 提取的 3 个 fallback 策略在 ai_recipe_parser.dart 中重复。 | 抽取 _extractJsonWithFallbacks() utility。 | HIGH | quality | pending | pending |
| lib/services/deduction_proposal_factory.dart:9 | medium | over-abstraction | 单 public 方法 forRecipe() 用途不明。 | 文档化或合并到 ProposalPlanner。 | HIGH | quality | pending | pending |
| lib/services/themealdb_service.dart:25 | high | missing-test | 整个 TheMealDB service 无单测。 | 新增 themealdb_service_test.dart with FakeHttpClient,覆盖 200/timeout/HTTP error/empty/malformed。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/utils/dashboard_greeting.dart:27 | medium | missing-edge-case | dashboardSubtitleFor 当前断言"今日和明日不同",placeholders 长度 5 时可能巧合相同。 | 改为按可控 dayNumber 推算预期文本断言。 | HIGH | test,carried-from-2026-05-07 | pending | pending |
| lib/utils/expiry_calculator.dart:13 | high | missing-edge-case | expiryFreshness 当 totalShelfLifeDays==0 / 负值返回 0.0 路径未测。 | 加边界测试: totalShelfLifeDays=0 / -1 / 极大(36500)。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/utils/json_object_list.dart:3 | medium | missing-test | decodeJsonObjectList 完全没有直接单元测试。 | 新建 json_object_list_test.dart 覆盖 list/non-list/混合/null。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/common/bottom_nav_bar.dart:1 | low | missing-test | bottom_nav_bar 仅在 widget_test 间接。 | 加单测 tap → onTap callback。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/common/bottom_nav_bar.dart:26 | low | rebuild | watch 整个 navigationProvider int OK;但内部 AnimatedContainer 颜色三元由 currentIndex 决定,未用 const。 | Selector / 提 const 子项 widget。 | LOW | perf,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:56 | high | rebuild | 同时 watch 5 个 provider,输入每字符触发 5 个 watch 联动。 | 拆出 _ResultsList 子 ConsumerWidget;debounce StateProvider。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/widgets/common/search_overlay.dart:331 | high | missing-error | foodDetailsResult.error 没有用户可见反馈。 | 显示一行可重试错误提示。 | LOW | ux,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/widgets/common/search_overlay.dart:1 | medium | missing-test | 593 行 search_overlay 无独立 widget 测试。 | 新建 search_overlay_test.dart。 | LOW | test,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/widgets/common/search_overlay.dart:55 | medium | selector-granularity | `ref.watch(searchProvider).trim()` 整 string watch。 | 引入 trimmedKeywordProvider = searchProvider.select((s)=>s.trim())。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/widgets/common/search_overlay.dart:262 | medium | long-function | `_buildResultsList` 86 行内大量 if/spread,可读性偏低;同时该文件的 _storageLabel 与项目其它 5 处重复。 | 把每个 section 抽成独立私有 build 方法,统一调用 `storageLabelFor`。 | LOW | quality,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/widgets/common/search_overlay.dart:299 | medium | list-builder | `ListView(shrinkWrap:true, children:[..., ...inventory.take(5).map])` shrinkWrap forces full layout。 | ListView.builder + itemExtent。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/widgets/common/search_overlay.dart:23 | low | rebuild | _SearchOverlayState inactive 时 return SizedBox.shrink,但仍订阅;overlay 一直挂 widget tree。 | 把 SearchOverlay 的 mount/visit 由父级 if(active) 控制。 | HIGH | perf,carried-from-2026-05-07 | pending | pending |
| lib/widgets/common/search_overlay.dart:224 | low | list-builder | `...history.map((term)=>ListTile(...))` 展开搜索历史(最多 10 条)。 | 保持但加 const Icon 等优化。 | LOW | perf,carried-from-2026-05-07 | blocked-by-high | pending |
| lib/widgets/common/swipe_reveal_delete_action.dart:1 | medium | missing-test | 140 行 swipe reveal 自定义组件无独立测试。 | 加 swipe_reveal_delete_action_test.dart。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/common/top_app_bar.dart:1 | low | missing-test | top_app_bar 无单测。 | 加渲染 + 搜索按钮 onTap。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/dashboard/curators_tip_card.dart:1 | low | missing-test | curators_tip_card 无测试。 | 新增基础渲染测试。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/dashboard/quick_action_card.dart:1 | low | missing-test | quick_action_card 仅在 widget_test 间接断言。 | 加 onTap 触发 + semanticLabel 检查。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/dashboard/stat_card.dart:1 | low | missing-test | stat_card 渲染 / accent color 无独立测。 | 加单测验证 title/value/subtitle 渲染。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/dashboard/storage_summary_card.dart:1 | low | missing-test | storage_summary_card 无渲染测试。 | 新增渲染冰箱/食品柜两种状态。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/shared/category_icon.dart:1 | low | missing-test | category_icon 多分类映射无单测。 | 加每个 FoodCategories 值的 icon 断言。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/shared/expiry_range_picker.dart:1 | medium | missing-test | expiry_range_picker 关键日期选择器只在 widget_test.dart 集成测试中接触。 | 拆出独立 widget 测试。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/shared/freshness_meter.dart:1 | medium | missing-test | freshness_meter 视觉组件无任何渲染测试。 | 新增 freshness_meter_test.dart。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/shared/recipe_image.dart:1 | low | missing-test | recipe_image 占位 / 错误状态未测。 | 加 null url placeholder + base64 / network 渲染。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |
| lib/widgets/shopping/smart_planner_card.dart:1 | low | missing-test | smart_planner_card 无独立 widget 测试。 | 新增渲染 + onTap 测试。 | LOW | test,carried-from-2026-05-07 | auto-approved | pending |

(Source = quality / perf / test / ux，可逗号分隔多命中；旧条目加 `carried-from-2026-05-07`)
(Decision = auto-approved / pending / blocked-by-high / approved / deferred / rejected)
(Status = pending / done / failed / reverted / skipped)

## Failed Agents

- Quality Explorer: Explore subagent 工具限制，仅分析约 9 个文件（~8% 覆盖率）；部分发现已入表，覆盖率不完整

## Failed Items

(none)

## Decisions Log

- **2026-05-26 LOW 批量批准**：用户批准全部 44 个 `auto-approved` LOW 项，Status 将在实施阶段逐步改为 `done`。blocked-by-high LOW 项待对应 HIGH 项决策后解锁。

## Final Verification

- [ ] flutter analyze 无新增 error / warning（基线已有的不算回归）
- [ ] flutter test：失败数 ≤ 基线失败数（不引入新失败）
- [ ] 至少 1 个新增测试覆盖 Test Explorer 盲点
- [ ] HIGH 项决策全部记录
- [ ] commit 数 < 受影响文件数
