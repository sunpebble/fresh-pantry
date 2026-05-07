# Agent Team 优化报告

**日期:** 2026-05-07
**Spec:** `2026-05-07-agent-team-optimization-design.md`
**状态:** 进行中

## Baseline

- `flutter analyze`: 0 error / 0 warning / 0 info (No issues found)
- `flutter test`: 148 / 148 passed

## Findings (合并表)

| File:Line | Severity | Category | Issue | Proposal | Risk | Source | Decision | Status |
|-----------|----------|----------|-------|----------|------|--------|----------|--------|
| lib/data/food_knowledge.dart:1 | medium | missing-test | FoodKnowledge.englishName / lookup 未单独测试。 | 新增 lookup() 命中/未命中 + englishName 单测。 | LOW | test | auto-approved | pending |
| lib/models/food_details.dart:1 | low | missing-test | FoodDetails.fromJson cacheVersion 字段处理未单测。 | 加 fromJson(cacheVersion=3) round-trip 测试。 | LOW | test | auto-approved | pending |
| lib/models/ingredient.dart:1 | low | missing-test | Ingredient.fromJson 容错(unknown storage 字符串、缺字段)未直接测试。 | 加 fromJson({'storage':'freezer'}) → fridge,缺字段使用默认。 | LOW | test | auto-approved | pending |
| lib/models/recipe.dart:147 | high | dead-code | `ScoredRecipe` 类(63 行,含 ==/hashCode/copyWith/toJson/fromJson)在 lib/ 下零引用,只有一处 model_equality_test 自测。 | 删除 `ScoredRecipe` 类及其测试。 | LOW | quality | auto-approved | done |
| lib/models/recipe.dart:1 | low | missing-test | Recipe.fromJson + ScoredRecipe.copyWith 部分字段未测。 | 补测 fromJson 缺字段 + copyWith 全字段。 | LOW | test | auto-approved | pending |
| lib/models/shopping_item.dart:1 | low | missing-test | ShoppingItem.fromJson 缺字段 / id 缺失行为未测。 | 新增 fromJson edge 单测。 | LOW | test | auto-approved | pending |
| lib/providers/custom_recipe_provider.dart:16 | medium | sync-io-in-build | CustomRecipeNotifier.build() 同步 jsonDecode 整个 recipe 列表。 | 改为 AsyncNotifier 或 main() 预热。 | HIGH | perf | approved | pending |
| lib/providers/food_details_provider.dart:64 | high | sync-io-in-build | detailsFor 在 FutureProvider body 中同步 jsonDecode + jsonEncode 整张 cache。 | isolate / compute 或 LRU memoization。 | HIGH | perf | approved | pending |
| lib/providers/food_details_provider.dart:64 | high | missing-error-path | client.lookup 抛异常 → fallback 路径靠 try/catch swallow,未单测。 [blocked by HIGH item in same file] | 在 food_details_provider_test 增加 client throws 测试。 | LOW | test | auto-approved | pending |
| lib/providers/food_details_provider.dart:168 | high | duplication | `_storageLabel(IconType)` 在 5 处独立实现,逻辑完全相同(switch fridge→'冰箱'/pantry→'食品柜'):dashboard_screen.dart:356、ingredient_detail_screen.dart:258、search_overlay.dart:546、ingredient_card.dart:47、food_details_provider.dart:168。 | 在 lib/models/storage_area.dart(或新增 lib/utils/storage_labels.dart)新增顶层 `String storageLabelFor(IconType)`,替换 5 处实现并删除私有副本。 | HIGH | quality | approved | done |
| lib/providers/food_details_provider.dart:45 | medium | provider-graph | foodDetailsProvider 是 family 但非 autoDispose;每次 ingredient identity 变就新建 entry。 | `FutureProvider.autoDispose.family`。 | HIGH | perf | approved | pending |
| lib/providers/food_details_provider.dart:175 | low | over-abstraction | `_normalizeCacheName` 包装 `name.trim().toLowerCase().replaceAll(\s+, ' ')`,与 recipe_provider.dart:42 的 pipeline 重复。 | 提取 `String normalizeCacheKey(String)` 到 lib/utils/。 | HIGH | quality | approved | done |
| lib/providers/inventory_provider.dart:124 | high | sync-io-in-build | InventoryNotifier.build() 通过 ref.read(sharedPreferencesProvider) 同步读取 prefs 并 jsonDecode 整张 inventory。 | 改为 AsyncNotifier + FutureProvider,或 main() 预 hydrate。 | HIGH | perf | approved | pending |
| lib/providers/inventory_provider.dart:143 | high | missing-error-path | _save 失败抛 StateError 未测试,_recordAddHistory 同失败路径未测。 [blocked by HIGH item in same file] | mock SharedPreferences setString 返回 false 触发 StateError。 | LOW | test | auto-approved | pending |
| lib/providers/inventory_provider.dart:188 | high | missing-test | InventoryNotifier.update + remove 边界(index<0 / 越界 / state 不变)未单独测试。 [blocked by HIGH item in same file] | 加测 update(-1)/update(99)/remove(-1)/remove(99) 不变更。 | LOW | test | auto-approved | pending |
| lib/providers/inventory_provider.dart:324 | high | sync-io-in-build | frequentItemsProvider 在 build 内 jsonDecode add_history 并跑 FoodKnowledge.lookup + sort。 | 改为 FutureProvider 或拆出预计算 cache。 | HIGH | perf | approved | pending |
| lib/providers/inventory_provider.dart:151 | medium | duplication | `_pendingPersistence` 顺序写队列模式在 inventory/shopping/custom_recipe provider 三处独立重复;命名不一(_queuePersistence vs _queueSave)。 | 提取为 mixin 或 helper class `PersistenceQueue`,三个 Notifier 复用,统一命名 `_queuePersistence`。 | HIGH | quality | approved | pending |
| lib/providers/inventory_provider.dart:239 | medium | provider-graph | 没有 autoDispose;derived (filtered*, foodDetailsProvider.family, recipeSearchRepositoryProvider) 也无 autoDispose。 | 对 derived 加 .autoDispose;core notifier 保留 keepAlive。 | HIGH | perf | approved | pending |
| lib/providers/inventory_provider.dart:243 | medium | provider-graph | 用 _addHistoryVersionProvider+ref.read 触发 frequentItems 重算(绕过 Riverpod 依赖图)。 | 把 add_history 也建成 NotifierProvider。 | HIGH | perf | approved | pending |
| lib/providers/inventory_provider.dart:324 | medium | missing-edge-case | frequentItemsProvider 测试覆盖排序但没测 count<2 过滤 / take(6) cap。 [blocked by HIGH item in same file] | 加测 8 个 frequent + 1 个 count=1 验证。 | LOW | test | auto-approved | pending |
| lib/providers/inventory_provider.dart:305 | low | naming | `FrequentItem` 模型类放在 inventory_provider.dart 文件末尾,与其他模型(放 lib/models/)位置不一致。 | 将 `FrequentItem` 移动到 lib/models/frequent_item.dart。 | HIGH | quality | approved | done |
| lib/providers/recipe_provider.dart:51 | high | missing-error-path | RecipeSearchRepository.searchByName 客户端抛异常未单独测。 [blocked by HIGH item in same file] | 加测 client.searchByName throws,确认外层不抛。 | LOW | test | auto-approved | pending |
| lib/providers/recipe_provider.dart:112 | medium | provider-graph | recipesProvider FutureProvider watch inventoryProvider,每次库存变动→重算并发起多次网络请求。 | 把搜索关键词稳定化。 | HIGH | perf | approved | pending |
| lib/providers/recipe_provider.dart:150 | medium | provider-graph | recommendedRecipesProvider watch 三个 provider 并完整重算 score 排序。 | 用 .select(items=>names set) 缩窄依赖。 | HIGH | perf | approved | pending |
| lib/providers/recipe_provider.dart:188 | medium | missing-edge-case | matchedIngredientCount 当 inventory 与 recipe 都为空时未直接测试。 [blocked by HIGH item in same file] | 加测空 inventory + 空 recipe.ingredients = 0。 | LOW | test | auto-approved | pending |
| lib/providers/recipe_provider.dart:17 | low | over-abstraction | `MealDbClient`/`FoodDetailsClient` 仅有一个生产实现但被多份测试 fake 实现,`TheMealDbClient` 仅是对 `TheMealDbService.searchByName` 的一行转发。 | 合并 `TheMealDbClient` 到 `TheMealDbService`,把后者改为可实例化、把抽象改名 `MealDbApi`。 | HIGH | quality | approved | pending |
| lib/providers/search_provider.dart:43 | high | missing-test | searchFoodDetailsProvider / SearchHistoryNotifier 几乎零覆盖。 [blocked by HIGH item in same file] | 新建 search_provider_test.dart 覆盖 history add/remove/clear/dedupe/cap10 + searchFoodDetails<2 字符。 | LOW | test | auto-approved | pending |
| lib/providers/search_provider.dart:17 | medium | missing-edge-case | filteredInventoryProvider 大小写/全空格/无匹配/空 keyword 路径未单测。 [blocked by HIGH item in same file] | 新增针对 filteredInventoryProvider 的 unit test。 | LOW | test | auto-approved | pending |
| lib/providers/search_provider.dart:43 | medium | provider-graph | searchFoodDetailsProvider 每键入一次重新构造 Ingredient,没有 debounce。 | autoDispose + debounce。 | HIGH | perf | approved | pending |
| lib/providers/shopping_provider.dart:65 | high | sync-io-in-build | ShoppingNotifier.build() 同步 jsonDecode + dedupe shopping list。 | 改为 AsyncNotifier;或 main 预热。 | HIGH | perf | approved | pending |
| lib/providers/shopping_provider.dart:116 | high | missing-test | ShoppingNotifier.remove / toggleCheck 缺单元测试。 [blocked by HIGH item in same file] | provider_logic_test.dart 加 remove unknown id + toggleCheck 切换持久化。 | LOW | test | auto-approved | pending |
| lib/providers/shopping_provider.dart:144 | medium | missing-edge-case | addFromSuggestion 空白/全空格输入返回 false 未测。 [blocked by HIGH item in same file] | 加测 addFromSuggestion('   ') 返回 false。 | LOW | test | auto-approved | pending |
| lib/providers/shopping_provider.dart:149 | medium | duplication | shopping ID 生成模式 `'si_${DateTime.now().millisecondsSinceEpoch}'` 在 5 处独立写出,且单位混用(microseconds/milliseconds)。 | 在 ShoppingItem 模型或 shopping_provider.dart 暴露统一 `String newShoppingItemId()`。 | HIGH | quality | approved | done |
| lib/screens/add_ingredient_screen.dart:51 | high | duplication/ui-duplication | [quality] `_storageIcons` 映射 `{fridge: Icons.kitchen, pantry: Icons.shelves}` 在 4 处重复:add_ingredient_screen.dart:53、batch_entry_screen.dart:42、storage_summary_card.dart:10、ingredient_card.dart:42。 ; [quality] `_storageLabels` 字典 `{fridge:'冰箱', pantry:'食品柜'}` 与 batch_entry_screen.dart:45 完全相同。 ; [ux] _storageLabels/_storageIcons 在多处重复声明。 | [quality] 在 lib/widgets/shared/category_icon.dart 旁新增顶层 `IconData storageIconFor(IconType)`,替换 4 处。 ; [quality] 删除两处私有 map,改用统一 storageLabelFor。 ; [ux] 抽 storage_area.dart 上的扩展方法。 | HIGH | quality,ux | approved | done |
| lib/screens/add_ingredient_screen.dart:289 | high | missing-loading | _save 同步执行,无 in-flight 状态;批量重复点击会创建多条。 [blocked by HIGH item in same file] | 加 _isSaving 标志置 disable 并显示 progress。 | LOW | ux | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:347 | high | ui-duplication | SnackBar 浮动样式在 6+ 处重复粘贴。 | 抽出 showAppSnackBar(success/info/error) 工具。 | HIGH | ux | approved | done |
| lib/screens/add_ingredient_screen.dart:790 | high | ui-duplication | _buildShelfDayChip / _buildCustomDateChip 与 PillChip 重叠。 | 复用同一 PillChip + selected 状态。 | HIGH | ux | approved | done |
| lib/screens/add_ingredient_screen.dart:878 | high | a11y | _buildSaveButton 用 GestureDetector + Container 自绘按钮,无 Semantics button label。 [blocked by HIGH item in same file] | 包 Semantics(button:true,label:'保存') 或换成 FilledButton。 | LOW | ux | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:917 | high | ui-duplication | _confirmDiscard AlertDialog 与多处几乎相同。 | 抽出 showAppConfirmDialog。 | HIGH | ux | approved | done |
| lib/screens/add_ingredient_screen.dart:289 | medium | long-function | `_save({navigateToInventory})` 方法体约 80 行,嵌套三元判断 `index` 选择,并混杂 SnackBar 构建。 [blocked by HIGH item in same file] | 拆分为 `_resolveEditIndex(...)`、`_buildIngredientFromForm()`、`_showAddedSnackBar(...)` 三个 helper。 | LOW | quality | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:391 | medium | rebuild | watch frequentItemsProvider 在大表单顶部,frequent 每次 add 触发整个表单 rebuild。 [blocked by HIGH item in same file] | 把 frequentItems 抽出成独立子 ConsumerWidget。 | LOW | perf | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:678 | medium | long-function | `_buildExpirationSection()` 方法体约 110 行,内含两层三元颜色判断重复 2 次。 [blocked by HIGH item in same file] | 提取 `_freshnessBadgeColors(double)` 返回 (bg,text);并把方法拆为 header/chips/selectedDate 三段子 widget。 | LOW | quality | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:1011 | medium | allocation-in-build | _buildFilledInput 每次 build 内嵌 Focus+Builder+AnimatedContainer+TextField,新建 BoxDecoration / Border / TextStyle。 [blocked by HIGH item in same file] | 抽成独立 StatelessWidget,InputDecoration / TextStyle 提为 static const。 | LOW | perf | auto-approved | pending |
| lib/screens/add_ingredient_screen.dart:597 | low | allocation-in-build | DropdownButton items 列表每次 build 重建 List<DropdownMenuItem>。 [blocked by HIGH item in same file] | 缓存或 const 化。 | LOW | perf | auto-approved | pending |
| lib/screens/batch_entry_screen.dart:30 | high | dead-code | `BatchEntryScreen` 整文件 432 行,grep 全 lib/test 仅自身命中,无任何 import/路由引用。 | 删除 lib/screens/batch_entry_screen.dart 整文件。 | LOW | quality | auto-approved | done |
| lib/screens/batch_entry_screen.dart:30 | high | missing-test | (obsolete: file deleted in Batch 1) 432 行批量录入屏幕完全无 widget 测试。 | 新增 batch_entry_screen_test.dart 覆盖 add+remove+confirmClearAll+save flow。 | LOW | test | auto-approved | skipped |
| lib/screens/batch_entry_screen.dart:123 | high | missing-loading | (obsolete: file deleted in Batch 1) _saveAll 异步循环但无 loading/error;按钮可重复点击。 | 加 _isSaving + 错误 catch + try/finally。 | LOW | ux | auto-approved | skipped |
| lib/screens/custom_recipe_form_screen.dart:111 | high | theme-inconsistency | 多处节标题用 GoogleFonts.manrope(18,w700) 而非 textTheme。 [blocked by HIGH item in same file] | 统一为 textTheme.titleLarge。 | LOW | ux | auto-approved | pending |
| lib/screens/custom_recipe_form_screen.dart:236 | high | missing-error | 保存失败仅 SnackBar"保存失败,请重试",无重试按钮。 | 统一错误恢复路径并提供 retry CTA。 | HIGH | ux | approved | pending |
| lib/screens/custom_recipe_form_screen.dart:550 | high | theme-inconsistency | _CoverImageHero 渐变纯黑硬编码,未走 colorScheme。 [blocked by HIGH item in same file] | 抽 const 或用 AppColors 衍生。 | LOW | ux | auto-approved | pending |
| lib/screens/custom_recipe_form_screen.dart:157 | medium | list-builder | `for (var i=0;...)` 把 ingredient/step 行铺成 Column children;输入项极少时可接受。 [blocked by HIGH item in same file] | 用 ListView.builder。 | LOW | perf | auto-approved | pending |
| lib/screens/custom_recipe_form_screen.dart:443 | medium | long-function | `_missingFields(...)` 方法 47 行,5 个布尔标志变量驱动一连串校验。 [blocked by HIGH item in same file] | 拆为 `_validateBasic` + `_validateIngredients` 返回各自缺失列表。 | LOW | quality | auto-approved | pending |
| lib/screens/dashboard_screen.dart:24 | high | missing-test | 553 行 dashboard 屏幕本身没有专属测试文件。 [blocked by HIGH item in same file] | 新增 dashboard_screen_test.dart 完整渲染 + 快捷动作 + 推荐食谱。 | LOW | test | auto-approved | pending |
| lib/screens/dashboard_screen.dart:29 | high | rebuild | DashboardScreen 同时 watch 6 个 provider;任一变动整屏 rebuild。 | 拆分为多个子 ConsumerWidget,各只 watch 自己的 provider。 | HIGH | perf | approved | pending |
| lib/screens/dashboard_screen.dart:84 | high | missing-loading | RefreshIndicator 仅 Future.delayed 模拟刷新,无真实加载/错误反馈。 | 接入真实数据源并显示 loading/error。 | HIGH | ux | approved | pending |
| lib/screens/dashboard_screen.dart:99 | high | allocation-in-build/theme-inconsistency | [perf] 每次 build 都 new 一堆 GoogleFonts/BoxDecoration/BorderRadius/withValues 颜色。 ; [ux] 问候语用 GoogleFonts.plusJakartaSans 写死 fontSize:30,绕过 textTheme.displayMedium(28)。 [blocked by HIGH item in same file] | [perf] 抽 static const TextStyle 或顶层常量。 ; [ux] 改用 Theme.of(context).textTheme.displayMedium。 | LOW | perf,ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:154 | high | theme-inconsistency | "紧急关注"用 urgentAttentionBackground.withValues(alpha:0.5) 直接调,层级混乱。 | 直接使用 errorContainer 或新增 token urgentSurface。 | HIGH | ux | approved | pending |
| lib/screens/dashboard_screen.dart:177 | high | theme-inconsistency | "紧急关注"内嵌 GoogleFonts.plusJakartaSans 与 textTheme.titleLarge(20) 重复。 [blocked by HIGH item in same file] | 替换为 Theme.of(context).textTheme.titleLarge。 | LOW | ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:186 | high | list-builder | `for (final (index, item) in expiringItems.indexed)` 把全部过期项展开成 Column,无虚拟化。 [blocked by HIGH item in same file] | 改用 SliverList.builder 或外层 CustomScrollView+SliverList.builder。 | LOW | perf | auto-approved | pending |
| lib/screens/dashboard_screen.dart:295 | high | theme-inconsistency | "存储概况"等节标题字号 22 在 textTheme 不存在。 [blocked by HIGH item in same file] | 统一节标题为 textTheme.headlineSmall 或 titleLarge。 | LOW | ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:302 | high | missing-empty-state | storageAreas 为空时无视觉占位。 [blocked by HIGH item in same file] | 增加 empty state。 | LOW | ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:323 | high | missing-empty-state | recentItems 为空时直接渲染 0 项。 [blocked by HIGH item in same file] | 增加"暂无最近添加"empty state。 | LOW | ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:363 | high | duplication/ui-duplication | [quality] `_addToShoppingList(Ingredient)` 在 dashboard_screen.dart:363、inventory_screen.dart:40、ingredient_detail_screen.dart:73 三处实现几乎完全一致。 ; [ux] _addToShoppingList 与 inventory_screen.dart:40 几乎完全重复。 | [quality] 在 ShoppingNotifier 上新增 `Future<bool> addFromIngredient(Ingredient)`,3 个屏幕替换为一行调用。 ; [ux] 抽 ShoppingListMutator 工具。 | HIGH | quality,ux | approved | done |
| lib/screens/dashboard_screen.dart:506 | high | responsive | _RecipeShortcutTile 固定 width:44 height:44 + 大量内容。 [blocked by HIGH item in same file] | Wrap inner content 或缩小 left badge。 | LOW | ux | auto-approved | pending |
| lib/screens/dashboard_screen.dart:154 | medium | long-function | "紧急关注" Container 内联约 130 行,build 方法整体超长(约 320 行)。 [blocked by HIGH item in same file] | 抽取 `_UrgentAttentionSection` StatelessWidget。 | LOW | quality | auto-approved | pending |
| lib/screens/dashboard_screen.dart:302 | medium | list-builder | `for (final (index, area) in storageAreas.indexed)` 同步展开 storage cards。 [blocked by HIGH item in same file] | 用 ListView.builder 或 SliverList.builder。 | LOW | perf | auto-approved | pending |
| lib/screens/dashboard_screen.dart:323 | low | list-builder | recentItems 展开成 List<Widget>(实际只取 2 条)。 [blocked by HIGH item in same file] | take(2) 已限定数量,可保持但加 const 优化。 | LOW | perf | auto-approved | pending |
| lib/screens/dashboard_screen.dart:352 | low | duplication | `_iconForCategory` 仅是对 `categoryIconFor` 的一行 wrapper,无新行为。 [blocked by HIGH item in same file] | 删除 `_iconForCategory`,直接调用 `categoryIconFor(item.category)`。 | LOW | quality | auto-approved | pending |
| lib/screens/dashboard_screen.dart:375 | low | duplication | 3 处 `category: item.category ?? '其他'` 字面量魔法字符串,应使用现有 `FoodCategories.other` 常量。 [blocked by HIGH item in same file] | 替换 3 处为 `item.category ?? FoodCategories.other`。 | LOW | quality | auto-approved | done |
| lib/screens/dashboard_screen.dart:393 | low | long-function | `_showRecipeSheet` 87 行 build 一个 modal sheet。 [blocked by HIGH item in same file] | 抽 `_RecipeRecommendationSheet` 私有 widget。 | LOW | quality | auto-approved | pending |
| lib/screens/ingredient_detail_screen.dart:206 | high | responsive | Container height:220 hero 图固定高。 [blocked by HIGH item in same file] | 改 AspectRatio(16/9) 或 LayoutBuilder。 | LOW | ux | auto-approved | pending |
| lib/screens/ingredient_detail_screen.dart:329 | high | responsive | LayoutBuilder 阈值 360 硬编码;且 SizedBox(width:184) 在中等屏可能挤占。 | 抽 breakpoint 常量。 | HIGH | ux | approved | pending |
| lib/screens/ingredient_detail_screen.dart:163 | medium | selector-granularity | watch 整个 inventoryProvider 仅为找当前 item 副本。 | .select((items)=>items[index])。 | HIGH | perf | approved | pending |
| lib/screens/ingredient_detail_screen.dart:60 | low | naming | inventory_screen.dart:27 用 `_indexOfInventoryItem`,ingredient_detail_screen.dart:60 用 `_indexOf`,均封装 `inventoryIndexOf(...)`。 [blocked by HIGH item in same file] | 统一为 `_indexOfInventoryItem` 或直接调用顶层 `inventoryIndexOf`。 | LOW | quality | auto-approved | pending |
| lib/screens/inventory_screen.dart:22 | high | missing-loading | _onRefresh 仅 800ms delay,无真实数据加载/错误显示。 | 集成 provider 加载状态。 | HIGH | ux | approved | pending |
| lib/screens/inventory_screen.dart:31 | high | duplication/ui-duplication | [quality] `_shoppingItemFor(Ingredient)` 在 inventory_screen.dart:31 与 ingredient_detail_screen.dart:64 完全相同。 ; [ux] _shoppingItemFor 与 ingredient_detail_screen.dart:64 重复。 | [quality] 提取为 `ShoppingItem.fromIngredient(Ingredient)` 工厂或顶层函数。 ; [ux] 抽 ShoppingItem.fromIngredient 工厂。 | HIGH | quality,ux | approved | done |
| lib/screens/inventory_screen.dart:125 | high | selector-granularity | watch 整个 filteredByCategoryProvider,任一字段变动整屏 rebuild。 | 在 item 级用 select 或拆 family provider。 | HIGH | perf | approved | pending |
| lib/screens/inventory_screen.dart:144 | high | theme-inconsistency | 标题使用 GoogleFonts.plusJakartaSans fontSize:32 与 displayLarge(32) 重复定义。 [blocked by HIGH item in same file] | 改用 textTheme.displayLarge。 | LOW | ux | auto-approved | pending |
| lib/screens/my_recipes_screen.dart:23 | high | missing-empty-state | empty 文案过于简陋。 [blocked by HIGH item in same file] | 提供 empty illustration + 引导按钮。 | LOW | ux | auto-approved | pending |
| lib/screens/my_recipes_screen.dart:1 | medium | missing-test | 仅 custom_recipe_flow_test 触及 list 渲染。 [blocked by HIGH item in same file] | 加测空状态 CTA + 多食谱排序。 | LOW | test | auto-approved | pending |
| lib/screens/my_recipes_screen.dart:55 | medium | selector-granularity | _MyRecipeCard.build 中 watch 整个 inventoryProvider 给每张卡。 | 把 matchedCount 提到顶层计算。 | HIGH | perf | approved | pending |
| lib/screens/recipe_detail_screen.dart:115 | high | responsive | SliverAppBar expandedHeight:240 在小屏极易遮挡内容。 [blocked by HIGH item in same file] | MediaQuery 适配或响应式比例。 | LOW | ux | auto-approved | pending |
| lib/screens/recipe_detail_screen.dart:138 | high | a11y | hero 占位 Icon 缺 semanticLabel,且无图片 alt。 [blocked by HIGH item in same file] | RecipeImage 已支持 semanticLabel。 | LOW | ux | auto-approved | pending |
| lib/screens/recipe_detail_screen.dart:148 | high | list-builder | SliverChildListDelegate 一次性铺所有 ingredients+steps;且 inventoryNames Set 在 build 内重算。 | 拆 SliverList.builder,把 inventoryNames 用 useMemoized 或外提。 | HIGH | perf | approved | pending |
| lib/screens/recipe_detail_screen.dart:194 | high | a11y | "一键补齐食材"用 GestureDetector + Container 实现按钮无 Semantics。 [blocked by HIGH item in same file] | 包 Semantics 或改用 FilledButton/InkWell。 | LOW | ux | auto-approved | pending |
| lib/screens/recipe_detail_screen.dart:482 | high | allocation-in-build/ui-duplication | [perf] _buildChip / _buildMetadataItem 每次 build new TextStyle/BoxDecoration。 ; [ux] _buildChip 与多处重复。 (Batch 3: ui-duplication 已通过 PillChip 抽取解决;perf 子项 _buildMetadataItem allocation 仍未处理,留待后续 perf 批次。) | [perf] 抽 const 子 widget。 ; [ux] 抽公共 PillChip widget。 | HIGH | perf,ux | approved | done |
| lib/screens/recipe_detail_screen.dart:1 | medium | missing-test | 506 行 recipe_detail_screen 仅有 custom_recipe_flow_test 间接测试。 [blocked by HIGH item in same file] | 加测 step toggle 持久化 + 进度展示 0/0 边界。 | LOW | test | auto-approved | pending |
| lib/screens/recipe_detail_screen.dart:102 | medium | selector-granularity | watch 整个 inventoryProvider,但只用名字集合。 | inventoryNamesProvider 或 .select。 | HIGH | perf | approved | pending |
| lib/screens/recipe_detail_screen.dart:464 | medium | duplication | `_ingredientNameMatchesInventory`/`_normalizedIngredientName`/`inventoryNames = inventory.map(...)` 与 recipe_provider.dart 中辅助函数是同一算法的两份私有实现。 | 把 recipe_provider.dart 中的辅助函数改为顶层公开函数,recipe_detail_screen.dart 删本地副本。 | HIGH | quality | approved | pending |
| lib/screens/recipe_detail_screen.dart:100 | low | long-function | `build` 方法 248 行,嵌套 SliverPadding/SliverList 内含大量 inline。 [blocked by HIGH item in same file] | 拆出 `_buildHeader`、`_buildMissingBanner`、`_buildIngredientsSection`、`_buildStepsSection`。 | LOW | quality | auto-approved | pending |
| lib/screens/shopping_list_screen.dart:32 | high | rebuild | 同时 watch groupedShoppingProvider + shoppingProvider + checkedCountProvider + uncheckedCountProvider。 | 只 watch groupedShoppingProvider 派生 counts。 | HIGH | perf | approved | pending |
| lib/screens/shopping_list_screen.dart:48 | high | missing-loading | RefreshIndicator 假刷新。 | 接入真实加载/错误态。 | HIGH | ux | approved | pending |
| lib/screens/shopping_list_screen.dart:71 | high | theme-inconsistency | fontSize:32 重复 displayLarge。 [blocked by HIGH item in same file] | 改用 textTheme.displayLarge。 | LOW | ux | auto-approved | pending |
| lib/screens/shopping_list_screen.dart:88 | high | a11y | "清理已购"GestureDetector + Container 无 Semantics 与 tooltip。 [blocked by HIGH item in same file] | 包 Semantics(button:true,label:'清理已购')。 | LOW | ux | auto-approved | pending |
| lib/screens/shopping_list_screen.dart:174 | high | list-builder | `SliverChildListDelegate([for (final entry in groupedItems.entries) _buildCategorySection])` 同步实例化所有分类。 [blocked by HIGH item in same file] | 改 SliverChildBuilderDelegate。 | LOW | perf | auto-approved | pending |
| lib/screens/shopping_list_screen.dart:184 | high | dead-code/ui-duplication | [quality] "卡博纳拉意面" hard-coded SmartPlannerCard 直接传 MockData.recipes.first,与购物清单内容无关。 ; [ux] SmartPlannerCard 标题硬编码"卡博纳拉意面",非动态推荐。 (Batch 1: dropped the dead `recipeName` arg per #5; UX dynamic-recommendation work remains pending in a later batch.) | [quality] 删除 SmartPlannerCard 调用,或改为依据 recommendedRecipesProvider 动态生成。 ; [ux] 由 provider 提供推荐或在无推荐时隐藏。 | HIGH | quality,ux | approved | done |
| lib/screens/shopping_list_screen.dart:417 | high | ui-duplication | "加入库存"逻辑与 inventory_screen 形成镜像;Ingredient 构造重复。 | 抽 IngredientFactory 或 service 方法。 | HIGH | ux | approved | pending |
| lib/screens/shopping_list_screen.dart:375 | medium | list-builder | `for (final item in items)` 在每个分类内展开全部 ShoppingItemTile。 [blocked by HIGH item in same file] | 每分类内部也改为 ListView/SliverList.builder。 | LOW | perf | auto-approved | pending |
| lib/screens/shopping_list_screen.dart:397 | medium | long-function | `_onItemChecked` 方法 65 行,内含 SnackBar action 闭包再构造 Ingredient + 第二个嵌套 SnackBar,嵌套 4 层。 [blocked by HIGH item in same file] | 把 SnackBar action 内部的 inventory-add 逻辑提取为 `_addItemToInventory(name, imageUrl)` 方法。 | LOW | quality | auto-approved | pending |
| lib/services/open_food_facts_service.dart:13 | high | dead-code | `FoodSearchResult.category` 字段在唯一调用方(add_ingredient_screen.dart:175)只读 `imageUrl`,grep 全项目 `result.category`/`?.category` 零命中。 | 删除 `FoodSearchResult.category` 字段及其在 searchByName 中的赋值/解析。 | HIGH | quality | approved | done |
| lib/services/themealdb_service.dart:25 | high | missing-test | 整个 TheMealDB service 无单测。 [blocked by HIGH item in same file] | 新增 themealdb_service_test.dart with FakeHttpClient,覆盖 200/timeout/HTTP error/empty/malformed。 | LOW | test | auto-approved | pending |
| lib/services/themealdb_service.dart:61 | high | dead-code | `searchByIngredient`/`random`/`lookupById`(对外)三个 public static 方法在 lib/test 全无外部调用。 | 删除 `searchByIngredient`、`random`,并将 `lookupById` 改为私有(仅供 searchByIngredient 内部使用,删除前者后也可删它)。 | HIGH | quality | approved | done |
| lib/services/themealdb_service.dart:232 | medium | duplication | `_fetch` HTTP 重试方法在 themealdb_service.dart:232 和 open_food_facts_service.dart:291 实现几乎一致;catch 块在两个 service 共出现 7 次。 | 提取 `Future<http.Response> fetchWithRetry(Uri, ...)` 到 lib/services/_http.dart。 | HIGH | quality | approved | done |
| lib/services/themealdb_service.dart:255 | medium | duplication | `_asMap`/`_asList`/`_asString` 三个 JSON 安全转型助手在 themealdb_service.dart 与 open_food_facts_service.dart 完全相同。 | 提取到 lib/utils/json_object_list.dart 或新增 lib/utils/json_cast.dart。 | HIGH | quality | approved | done |
| lib/theme/app_colors.dart:10 | medium | dead-code | `primaryFixedDim`、`secondaryFixedDim`、`tertiaryFixed` 三个常量 grep 整个 lib 零引用(只在 app_colors.dart 自身定义)。 | 在 app_colors.dart 中删除这 3 行常量。 | LOW | quality | auto-approved | done |
| lib/theme/app_theme.dart:58 | high | theme-inconsistency | 缺少集中的 spacing/radius/elevation token,所有 screen 自由使用魔术数字。 | 新增 AppSpacing/AppRadius 常量类。 | HIGH | ux | approved | pending |
| lib/utils/dashboard_greeting.dart:27 | medium | missing-edge-case | dashboardSubtitleFor 当前断言"今日和明日不同",placeholders 长度 5 时可能巧合相同。 | 改为按可控 dayNumber 推算预期文本断言。 | HIGH | test | approved | pending |
| lib/utils/expiry_calculator.dart:13 | high | missing-edge-case | expiryFreshness 当 totalShelfLifeDays==0 / 负值返回 0.0 路径未测。 | 加边界测试: totalShelfLifeDays=0 / -1 / 极大(36500)。 | LOW | test | auto-approved | pending |
| lib/utils/json_object_list.dart:3 | medium | missing-test | decodeJsonObjectList 完全没有直接单元测试。 | 新建 json_object_list_test.dart 覆盖 list/non-list/混合/null。 | LOW | test | auto-approved | pending |
| lib/widgets/common/bottom_nav_bar.dart:84 | high | a11y | 选中颜色直接 Colors.white,与 onPrimary token 不一致。 | 改用 AppColors.onPrimary。 | LOW | ux | auto-approved | pending |
| lib/widgets/common/bottom_nav_bar.dart:1 | low | missing-test | bottom_nav_bar 仅在 widget_test 间接。 | 加单测 tap → onTap callback。 | LOW | test | auto-approved | pending |
| lib/widgets/common/bottom_nav_bar.dart:26 | low | rebuild | watch 整个 navigationProvider int OK;但内部 AnimatedContainer 颜色三元由 currentIndex 决定,未用 const。 | Selector / 提 const 子项 widget。 | LOW | perf | auto-approved | pending |
| lib/widgets/common/category_chips.dart:138 | high | theme-inconsistency | 直接 TextStyle(fontSize:13) 不走 textTheme。 | 用 Theme.of(context).chipTheme 或 textTheme.labelLarge。 | LOW | ux | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:56 | high | rebuild | 同时 watch 5 个 provider,输入每字符触发 5 个 watch 联动。 | 拆出 _ResultsList 子 ConsumerWidget;debounce StateProvider。 | HIGH | perf | approved | pending |
| lib/widgets/common/search_overlay.dart:69 | high | theme-inconsistency | Colors.black.withValues 多处用作阴影,而其他卡片使用 AppColors.onSurface.withValues。 [blocked by HIGH item in same file] | 统一阴影色。 | LOW | ux | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:331 | high | missing-error | foodDetailsResult.error 没有用户可见反馈。 [blocked by HIGH item in same file] | 显示一行可重试错误提示。 | LOW | ux | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:1 | medium | missing-test | 593 行 search_overlay 无独立 widget 测试。 [blocked by HIGH item in same file] | 新建 search_overlay_test.dart。 | LOW | test | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:55 | medium | selector-granularity | `ref.watch(searchProvider).trim()` 整 string watch。 | 引入 trimmedKeywordProvider = searchProvider.select((s)=>s.trim())。 | HIGH | perf | approved | pending |
| lib/widgets/common/search_overlay.dart:262 | medium | long-function | `_buildResultsList` 86 行内大量 if/spread,可读性偏低;同时该文件的 _storageLabel 与项目其它 5 处重复。 [blocked by HIGH item in same file] | 把每个 section 抽成独立私有 build 方法,统一调用 `storageLabelFor`。 | LOW | quality | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:299 | medium | list-builder | `ListView(shrinkWrap:true, children:[..., ...inventory.take(5).map])` shrinkWrap forces full layout。 [blocked by HIGH item in same file] | ListView.builder + itemExtent。 | LOW | perf | auto-approved | pending |
| lib/widgets/common/search_overlay.dart:23 | low | rebuild | _SearchOverlayState inactive 时 return SizedBox.shrink,但仍订阅;overlay 一直挂 widget tree。 | 把 SearchOverlay 的 mount/visit 由父级 if(active) 控制。 | HIGH | perf | approved | pending |
| lib/widgets/common/search_overlay.dart:224 | low | list-builder | `...history.map((term)=>ListTile(...))` 展开搜索历史(最多 10 条)。 [blocked by HIGH item in same file] | 保持但加 const Icon 等优化。 | LOW | perf | auto-approved | pending |
| lib/widgets/common/status_badge.dart:5 | high | dead-code | 公共 widget `StatusBadge` 全项目零引用(alert_card.dart 用的是同名私有 `_StatusBadge`)。 | 删除 lib/widgets/common/status_badge.dart 整文件。 | LOW | quality | auto-approved | done |
| lib/widgets/common/status_badge.dart:36 | high | theme-inconsistency | (obsolete: file deleted in Batch 1) TextStyle 写死 fontSize:11/w600,与项目其他 badge 不统一。 | 抽出 AppTypography.badgeLabel 或用 labelSmall。 | LOW | ux | auto-approved | skipped |
| lib/widgets/common/status_badge.dart:1 | low | missing-test | (obsolete: file deleted in Batch 1) status_badge 无单测。 | 加颜色 / label 渲染单测。 | LOW | test | auto-approved | skipped |
| lib/widgets/common/swipe_reveal_delete_action.dart:1 | medium | missing-test | 140 行 swipe reveal 自定义组件无独立测试。 | 加 swipe_reveal_delete_action_test.dart。 | LOW | test | auto-approved | pending |
| lib/widgets/common/top_app_bar.dart:21 | high | a11y | Image.asset 缺 semanticLabel。 | 加 semanticLabel:'食材管家应用图标' 或 ExcludeSemantics。 | LOW | ux | auto-approved | pending |
| lib/widgets/common/top_app_bar.dart:1 | low | missing-test | top_app_bar 无单测。 | 加渲染 + 搜索按钮 onTap。 | LOW | test | auto-approved | pending |
| lib/widgets/dashboard/alert_card.dart:69 | high | theme-inconsistency | name 用 GoogleFonts.manrope(fontSize:17) 偏离 textTheme。 | 用 titleMedium(16) 或新增 token。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/alert_card.dart:99 | high | theme-inconsistency | storageTag 内联硬编码 fontSize:9/letterSpacing:0.8。 | 统一 micro-label token。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/alert_card.dart:148 | low | allocation-in-build | LayoutBuilder 内每次 build new buttons list + Row/Wrap。 | 抽出 const sub-widget;缓存 buttons。 | LOW | perf | auto-approved | pending |
| lib/widgets/dashboard/curators_tip_card.dart:43 | high | theme-inconsistency | bottomLabel fontSize:10 letterSpacing:2 不统一。 | 抽 textTheme.labelSmall。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/curators_tip_card.dart:1 | low | missing-test | curators_tip_card 无测试。 | 新增基础渲染测试。 | LOW | test | auto-approved | pending |
| lib/widgets/dashboard/quick_action_card.dart:32 | high | responsive | 内部 Column 在窄屏 + 长 subtitle 时易溢出(无 maxLines/ellipsis)。 | 给 title/subtitle 加 maxLines+ellipsis。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/quick_action_card.dart:1 | low | missing-test | quick_action_card 仅在 widget_test 间接断言。 | 加 onTap 触发 + semanticLabel 检查。 | LOW | test | auto-approved | pending |
| lib/widgets/dashboard/recent_addition_item.dart:31 | high | theme-inconsistency | 普通 TextStyle 无 GoogleFonts,字体不一致。 | 全部改用 textTheme。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/stat_card.dart:1 | low | missing-test | stat_card 渲染 / accent color 无独立测。 | 加单测验证 title/value/subtitle 渲染。 | LOW | test | auto-approved | pending |
| lib/widgets/dashboard/storage_summary_card.dart:43 | high | theme-inconsistency | 系统默认字体 TextStyle(fontWeight:.w700,fontSize:17)。 | 用 textTheme.titleMedium。 | LOW | ux | auto-approved | pending |
| lib/widgets/dashboard/storage_summary_card.dart:1 | low | missing-test | storage_summary_card 无渲染测试。 | 新增渲染冰箱/食品柜两种状态。 | LOW | test | auto-approved | pending |
| lib/widgets/inventory/ingredient_card.dart:88 | high | theme-inconsistency | name 用裸 TextStyle 无 GoogleFonts。 [blocked by HIGH item in same file] | 改用 textTheme.titleMedium / Manrope。 | LOW | ux | auto-approved | pending |
| lib/widgets/inventory/ingredient_card.dart:20 | low | duplication | `_badgeBg`/`_badgeText` 颜色 switch 与 widgets/common/status_badge.dart 的语义相同(若 StatusBadge 不删除可复用之)。 | 抽取 `({Color bg, Color text}) freshnessBadgeColors(FreshnessState)` 到 utils/,两处共享。 | HIGH | quality | approved | pending |
| lib/widgets/inventory/ingredient_card.dart:53 | low | allocation-in-build | 大量 BoxDecoration/TextStyle/Container 在 build 内创建(每行库存项)。 [blocked by HIGH item in same file] | 抽 const 子部件、把 colors 解构到 final。 | LOW | perf | auto-approved | pending |
| lib/widgets/shared/category_icon.dart:1 | low | missing-test | category_icon 多分类映射无单测。 | 加每个 FoodCategories 值的 icon 断言。 | LOW | test | auto-approved | pending |
| lib/widgets/shared/expiry_range_picker.dart:1 | medium | missing-test | expiry_range_picker 关键日期选择器只在 widget_test.dart 集成测试中接触。 | 拆出独立 widget 测试。 | LOW | test | auto-approved | pending |
| lib/widgets/shared/freshness_meter.dart:60 | high | theme-inconsistency | 仍使用裸 TextStyle(无 GoogleFonts)。 | 替换为 textTheme.labelSmall + Manrope。 | LOW | ux | auto-approved | pending |
| lib/widgets/shared/freshness_meter.dart:1 | medium | missing-test | freshness_meter 视觉组件无任何渲染测试。 | 新增 freshness_meter_test.dart。 | LOW | test | auto-approved | pending |
| lib/widgets/shared/recipe_image.dart:1 | low | missing-test | recipe_image 占位 / 错误状态未测。 | 加 null url placeholder + base64 / network 渲染。 | LOW | test | auto-approved | pending |
| lib/widgets/shared/recipe_image.dart:64 | low | allocation-in-build | Image.network 无 cacheWidth/Height,导致全分辨率解码。 | 给固定尺寸场景传 cacheWidth=width.toInt()。 | LOW | perf | auto-approved | pending |
| lib/widgets/shopping/quick_add_field.dart:69 | high | a11y | suffixIcon IconButton 无 tooltip。 | 加 tooltip:'添加到购物清单'。 | LOW | ux | auto-approved | pending |
| lib/widgets/shopping/smart_planner_card.dart:7 | high | dead-code | `recipeName` 字段标记 `required` 但 build() 内零读取,仅在 shopping_list_screen.dart:186 传 '卡博纳拉意面' 这个硬编码占位。 | 删除 `recipeName` 字段及构造参数。 | HIGH | quality | approved | done |
| lib/widgets/shopping/smart_planner_card.dart:1 | low | missing-test | smart_planner_card 无独立 widget 测试。 [blocked by HIGH item in same file] | 新增渲染 + onTap 测试。 | LOW | test | auto-approved | pending |
| test/category_chips_test.dart:6 | low | missing-test | 仅 1 测试,onSelected 回调 / 选中样式未测。 | 加 tap 触发 onSelected + selected chip 颜色断言。 | LOW | test | auto-approved | pending |
| test/custom_recipe_flow_test.dart:574 | low | weak-assertion | "ignores repeated save taps while saving" 仅断言保存 1 条,未验证 button 真的被禁用。 | 增加对 ElevatedButton.onPressed==null 的状态断言。 | HIGH | test | approved | pending |
| test/dashboard_greeting_test.dart:16 | low | weak-assertion | subtitle 测试只断言 today!=tomorrow,未锁定 placeholder 内容。 | 用固定 dayNumber 推算预期。 | HIGH | test | approved | pending |
| test/expiry_calculator_test.dart:25 | low | missing-edge-case | expiryFreshness 仅测同日 + 7 天,缺 0/负 totalShelfLifeDays / 已过期 clamp 行为。 | 补 totalShelfLifeDays=0 → 0.0 / 已过期 → 0.0 / 极大。 | LOW | test | auto-approved | pending |
| test/ingredient_card_test.dart:9 | low | weak-assertion | 仅断言 imageUrl 不渲染 Image,缺 expiryLabel/freshness 状态视觉断言。 | 加 expiringSoon/expired 状态下 expiryLabel 与颜色断言。 | HIGH | test | approved | pending |
| test/inventory_screen_test.dart:25 | low | weak-assertion | findsNothing/textContaining 易因 UI 调整漏检。 | 改为正向断言保留组件的 ValueKey。 | HIGH | test | approved | pending |
| test/open_food_facts_service_test.dart:9 | low | missing-error-path | service 测试覆盖 200/empty/503 但未覆盖 timeout / network exception / malformed JSON。 | 加 _FakeHttpClient 抛 TimeoutException / FormatException 测 fallback null。 | LOW | test | auto-approved | pending |
| test/provider_logic_test.dart:48 | low | anti-pattern | "updates watched frequent items immediately after add completes" 用 await Future.microtask hack。 | 改为对 _addHistoryVersionProvider listen 直接等待变化。 | HIGH | test | approved | pending |
| test/provider_logic_test.dart:284 | low | weak-assertion | "concurrent duplicate adds without losing history count" 仅断言 count==2,未断言 inventory 长度 / 顺序。 | 加 expect(savedInventory, hasLength(2)) 与顺序断言。 | HIGH | test | approved | pending |
| test/quick_add_field_test.dart:15 | low | weak-assertion | 只断言 hint 出现且不显示 suggestions。 | 加输入"番茄"+提交,断言 shoppingProvider 增加一条。 | HIGH | test | approved | pending |
| test/system_ui_overlay_test.dart:16 | low | weak-assertion | 取 regions.first 但 regions 顺序非确定。 | 用 find.byKey 或具体 ancestor 定位。 | HIGH | test | approved | pending |
| test/widget_test.dart:28 | medium | anti-pattern | 873 行单文件混杂 dashboard/expiry-picker/search/AppShell 多领域测试。 | 拆分为 dashboard_screen_test / expiry_range_picker_test / search_overlay_integration_test。 | HIGH | test | approved | pending |
| test/widget_test.dart:28 | medium | weak-assertion | "App smoke test" 仅断言 `find.byType(FreshPantryApp)` 必然存在。 | 改为渲染后断言 dashboard 标题文字或 BottomNavigationBar。 | HIGH | test | approved | pending |
| test/widget_test.dart:381 | low | weak-assertion | "uses the item expiry label as badge" 断言 find.text('48H') 是 findsNothing 这种否定测试。 | 在 AlertCard 范围内 ancestor + descendant 双向断言 badge 文本。 | HIGH | test | approved | pending |

(Source = quality / perf / test / ux,可逗号分隔表示多 agent 命中)
(Decision = LOW: auto-approved / HIGH: pending / blocked-by-high(同文件存在 HIGH,需等其决策))
(Status = pending / done / failed / reverted)

## Failed Agents

(none)

## Failed Items

(none)

## Decisions Log

- 2026-05-07 LOW batch: 全部批准(43/43 auto-approved LOW,18 high + 6 medium + 19 low severity,涵盖 28 个文件)。
- 2026-05-07 HIGH batch: 全部批准(62/62 HIGH 项)。聚类概览:
  - **A. Provider 异步化 + autoDispose**(11 项):三个 Notifier sync prefs → AsyncNotifier;derived providers 加 .autoDispose;`_addHistoryVersionProvider` hack 重构
  - **B. 共享 UI 工具**(16 项):storageLabelFor / storageIconFor / ShoppingItem.fromIngredient / PillChip / showAppSnackBar / showAppConfirmDialog / fetchWithRetry
  - **C. 屏幕拆 ConsumerWidget**(10 项):Dashboard 拆子组件;ShoppingList 派生 counts;SearchOverlay 拆 _ResultsList;recipe_detail 引入 inventoryNamesProvider
  - **D. 加载/错误状态体系**(5 项):RefreshIndicator 接真实数据;_isSaving in-flight;custom_recipe_form retry CTA;SliverAppBar 响应式
  - **E. 测试体系重构**(12 项):widget_test.dart 873 行拆分;弱断言改强断言;Future.microtask hack 改 listen 等待
  - **F. HIGH dead-code 删除**(3 项):themealdb_service public methods、SmartPlannerCard.recipeName、FoodSearchResult.category
  - **G. 主题 token 体系**(2 项):新增 AppSpacing/AppRadius;dashboard "紧急关注" 用 errorContainer
  - **H. 杂项**(3 项):MealDbClient/TheMealDbService 合并;FrequentItem 移到 lib/models/;normalizeCacheKey 提取
- 2026-05-07 Unblock LOW: 因所有 HIGH 都被批准,60 条 `blocked-by-high` 全部解锁为 `auto-approved`(LOW 总计变为 103 条)。
- 2026-05-07 Batch 1 (dead-code 清理) 完成: 8 项 dead-code findings 实施完毕。3 个相关 follow-up findings(已删文件的 missing-test/missing-loading/theme-inconsistency)随之标记为 `skipped`(obsolete)。所有删除前都 grep 复核为零调用。`flutter analyze` 0 issues,`flutter test` 147/147 通过(基线 148,删除 ScoredRecipe 测试 -1)。
- 2026-05-08 Batch 2 (共享工具体系) 完成: 8 个 unit (2A-2H) 全部按计划落地,各自独立 commit。新增 utility:`lib/utils/storage_labels.dart`、`lib/utils/json_cast.dart`、`lib/utils/normalize_cache_key.dart`、`lib/services/_http.dart`,新增 model:`lib/models/frequent_item.dart`,扩展模型:`ShoppingItem.fromIngredient` 工厂 + `ShoppingItem.newId()` + `ShoppingNotifier.addFromIngredient`。10 项 finding 标记 done(覆盖 storage label/icon、`_storageIcons`/`_storageLabels` 字典、`_addToShoppingList`、`_shoppingItemFor`、shopping ID 生成、JSON cast、HTTP `_fetch` 重试、`_normalizeCacheName`、`FrequentItem` 位置、`'其他'` 魔法字符串)。`flutter analyze` 0 issues,`flutter test` 173/173 通过(基线 147 + 新增 26 个测试)。

## Final Verification

- [ ] flutter analyze 0 error / 0 warning
- [ ] flutter test all pass
- [ ] 至少 1 个新增测试覆盖 Test Explorer 盲点
- [ ] HIGH 项决策全部记录
- [ ] commit 数 < 受影响文件数
