# Flutter→iOS 对等缺口清单 (审计 2026-06-09, 51 confirmed)

> ## 进度更新 2026-06-09(第 2 轮:「直到结束」续做)
>
> 第 1 轮已补全部 High + 核心 Medium(库存编辑、Shopping 全 6、Inventory 6、Recipes 5、MealPlan/Dashboard/Waste 6、Settings 1)。本轮在其上继续:
>
> **本轮新补(构建 + 测试通过):**
> - Recipes **#3** 4-tab(探索/现有/用临期/我的,segmented)、**#4** 时间筛选(不限/≤15/≤30)、**#5** 忌口过滤(接 `DietaryPreferencesStore` + 顶栏忌口入口,设置项终于作用于列表)、**#7** 备料倍数(½×/1×/2×/3× 缩放展示 + 做菜扣减)、**#9** 详情「加入膳食计划」(7 天选择器 → `MealPlanStore.addDish`)。新纯函数 `RecipeMatching.rankedByAvailability`(现有 tab 排序,移植 `recommendedRecipesProvider`)。
> - Dashboard **#2** 今日推荐卡(+骨架屏)、**#3** 用临期兜底卡(`RecipeMatching.expiringFallback`)、**#6** 库存不足内联预览 + 「全部加入购物清单」。首页可推送菜谱详情(`navigationDestination(item:)`)。
> - Inventory **#1** 多选(长按进入,批量删除+撤销/批量加购/合并)、**#2** 合并批次(`InventoryStore.deleteMany`/`undoBatchRemoval`/`canMerge`/`mergeBatch`,移植 `mergeBatch` 求和+取较早到期)。
> - CrossCutting **同步状态横幅**:`ConnectivityMonitor`(NWPathMonitor,反应式离线检测)+ `SyncStatusBanner`(离线/同步中·N 条待同步,挂 RootView 顶部;待同步计数为最佳努力刷新)。
> - 低成本 parity:Dashboard 时段问候语(早安/午安/…,主厨。)、Shopping 添加重名内联反馈(修「静默关闭=假成功」)。
>
> **本轮明确暂缓(理由):**
> - Recipes **#10** 食材/步骤拖拽排序:`onMove` 仅在 `List`/`EditMode` 生效,需把复杂的自定义食谱表单整体改造(高风险),自用编辑价值低。
> - Dashboard **#4** 食材分类网格:网格本身易做,但其价值在「点分类→跳冰箱 tab 预置筛选」的跨 tab 下钻,需跨 tab 共享筛选意图状态(侵入);冰箱 tab 已有分类筛选 chip,边际价值低。
> - CrossCutting **全局搜索浮层**(重,且各域已有按名搜索)、**系统分享 intent**(需新建 Share Extension target + App Group + entitlements;剪贴板导入已覆盖常见路径)。
> - Settings **#2** 饮食偏好预设:推荐逻辑当前不消费 `categoryPreferences`,加了会是「死设置」;且偏家庭多人。
> - Auth/Household **9 项**(邀请/二维码/深链/红点/待处理邀请):纯多人协作,[[project_mode_self_use]] 自用无真实用户,价值最低。
> - 其余「low, 未复核」少量项(如 Waste Top 榜、备份剪贴板回退、Hero·N类)按价值暂留。


## Recipes (11)
- [HIGH] **缺少临期提醒 banner 与按库存/临期的排序**
  - 影响: 用户看不到「优先使用 N 件临期食材」的提醒条,也看不到卡片上的「临期·N」角标和按库存匹配度/临期清库存量的排序——失去了 App 减少浪费这一核心价值的可视化引导。
  - Flutter: apps/mobile/lib/screens/recipes_screen.dart:240-249 `_ExpiringBanner`(『优先使用 N 件临期食材』);:583-619 banner 实现;卡片角标 apps/mobile/lib/widgets/recipe_card.dart:486-522 `_ExpiringBadge`(『临期·N』)与进度条 _RecipeMeta:205-247;排序 recipe_provider.dart:113 `recipesRankedByExpiringUse` 与:183 `recommendedRecipesProvider`。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipesView.swift 无 banner;apps/ios/FreshPantry/DesignSystem/Components/RecipeCard.swift:6-7 注释明示『browse scope only — no ingredient-match progress bar or expiring badge in this phase』,卡片无进度条/临期角标;RecipesStore.swift 无 expiring/match 排序。蓝图 screens-recipes.md:16/19/153 均要求。
- [HIGH] **详情页缺少食材库存匹配高亮(已有/缺少)**
  - 影响: 在菜谱详情里,用户看不到每个食材是「已有」还是「缺少」,也看不到『已有 X/总数』的统计——无法一眼判断这道菜还差什么、能不能直接开做。
  - Flutter: apps/mobile/lib/screens/recipe_detail_screen.dart:158-165 计算 matched/missing;:465-539 `_IngredientsSection`(『已有 matched/total』);:609-699 `_IngredientRow`(缺少项 fkDangerSoft 高亮 + 『已有』/『缺少』pill + 勾/叉 status mark)。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift:238-251 `ingredientRow` 仅显示 name + amount,无库存匹配、无高亮、无『已有 X/总数』;FkSectionHeader(:222)只显示总数。grep 『已有/缺少/matchedIngredient/isAvailable』在 Recipes/ 详情内无命中。蓝图 screens-recipes.md:25/31-32 要求。
- [MEDIUM] **缺少 4-tab 子页(探索/现有/用临期/我的)**
  - 影响: 用户无法按「现有食材可做」「优先用临期食材」「我的自定义食谱」分别浏览菜谱;iOS 只有一个混合后的扁平浏览列表,失去了核心的发现入口,看不到「现有食材能做什么」和「该用哪些临期食材」这两个最关键的使用场景。
  - Flutter: apps/mobile/lib/screens/recipes_screen.dart:25 `enum _RecipeTab { expiring, available, explore, mine }`;:119-124 `list = switch(_tab){...}`;:328-361 `_TabRow`(探索/现有/用临期/我的 4 按钮)。数据源 apps/mobile/lib/providers/recipe_provider.dart:183 `recommendedRecipesProvider`(按库存匹配评分)与:113 `recipesRankedByExpiringUse`。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipesView.swift:149-270 `RecipesContent` 只渲染一个 `store.displayRecipes` 列表,无任何 tab/segmented control;RecipesStore.swift:94-100 `displayRecipes` 仅做 category/search/favorites 过滤,既无按库存匹配排序也无临期排序。蓝图 screens-recipes.md:16 明确要求 4 子页,未标注有意移除。
- [MEDIUM] **缺少烹饪时间筛选(不限/≤15/≤30 分钟)**
  - 影响: 用户无法按可用时间快速筛出「15 分钟内」「30 分钟内」的菜,失去了一个常用的实用过滤维度。
  - Flutter: apps/mobile/lib/screens/recipes_screen.dart:27 `enum _TimeFilter { all, fast15, fast30 }`;:139-143 过滤逻辑 `cookingMinutes <= 15/30`;:434-483 `_TimeFilterRow`(不限时间/⏱ 15 分钟内/⏱ 30 分钟内)。
  - iOS: 整个 apps/ios 内对 “15 分钟/30 分钟/不限时间/timeFilter” 的 grep 仅命中数据文件 Resources/howtocook.json;RecipesStore.swift:17-19 的过滤状态只有 categoryFilter/searchQuery/favoritesOnly,无时间筛选。蓝图 screens-recipes.md:15-17 要求该筛选。
- [MEDIUM] **缺少忌口(不吃的食材)过滤与入口**
  - 影响: 用户在 iOS 上虽能在「设置」里编辑忌口关键词,但这些关键词完全不会作用于菜谱列表——含忌口食材的菜谱不会被隐藏;同时菜谱页顶栏没有忌口快捷入口。用户设置了忌口却看不到任何过滤效果。
  - Flutter: apps/mobile/lib/screens/recipes_screen.dart:161-168 在所有 tab 上 `recipeHasExcludedIngredient(r, exclusions)` 过滤;:195-206 顶栏 `recipe_dietary_action` 按钮打开 `_DietaryExclusionsSheet`(:721 起);过滤函数 apps/mobile/lib/providers/recipe_provider.dart:40 `recipeHasExcludedIngredient`。
  - iOS: DietaryPreferencesStore 仅在 apps/ios/FreshPantry/Features/Settings/SettingsView.swift:168 通过 DietaryExclusionEditor 暴露编辑;grep 确认 RecipesStore.swift / RecipesView.swift 内无任何 dietary/exclusion 引用,displayRecipes(RecipesStore.swift:94-100)不应用忌口过滤,菜谱顶栏(RecipesView.swift:39-49)只有「+」按钮无忌口入口。属功能未接线的回退。
- [MEDIUM] **详情页缺少『一键加购缺少的 N 件』**
  - 影响: 用户在菜谱里无法把缺失食材一键加入购物清单,只能手动逐个去购物清单添加,打断了「看菜谱→缺什么→去买」的闭环。
  - Flutter: apps/mobile/lib/screens/recipe_detail_screen.dart:277-286 当 missing 非空显示 `_AddMissingCta`;:85-115 `_addMissingToCart` 调 `shoppingProvider.notifier.add(...)`;:736-794 `_AddMissingCta` UI(『一键加购缺少的 N 件』)。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift 内 grep 『addMissing/一键加购/缺少的/shopping』均无命中;详情页底部只有单一『做菜』CTA(:121-145)。蓝图 screens-recipes.md:25/33 要求。
- [MEDIUM] **详情页缺少备料倍数(½×/1×/2×/3×)缩放**
  - 影响: 用户无法按份量缩放食材用量(如做双倍),展示与加购的用量都固定为原始配方,做多人份时需自己心算。
  - Flutter: apps/mobile/lib/screens/recipe_detail_screen.dart:63 `_scaleFactor`;:459-460 `_scalePresets [0.5,1.0,2.0,3.0]`;:542-607 `_ScaleSelector`/`_ScaleChip`;:526 `ingredient.scaledBy(scaleFactor)`;:283 加购按 `scaledBy(_scaleFactor)`。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift:238-251 食材行直接显示 `ingredient.amount`,无缩放控件;该文件内 grep『scaleFactor/scaledBy/备料/倍数』唯一命中是 :228 一条无关的 hairline 代码。蓝图 screens-recipes.md:25/31 与迁移注意 :195(invariant 4)要求。
- [MEDIUM] **详情页缺少烹饪步骤勾选清单与进度条**
  - 影响: 用户做菜时无法点按步骤标记完成、看不到完成进度(done/total + 进度条),失去了边做边勾的清单体验;对应的『开始烹饪』CTA 也缺失。
  - Flutter: apps/mobile/lib/screens/recipe_detail_screen.dart:59 `Set<int> _completedSteps`;:75-83 `_toggleStep`;:167-169 stepProgress;:796-865 `_StepsSection`(LinearProgressIndicator + done/total);:867-933 `_StepRow`(可点完成、完成后划线);:1000-1044 `_StartCookingButton`(『开始烹饪』)。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift:255-284 `stepsSection`/`stepRow` 只是静态编号步骤,无可点完成、无进度条;grep『completedStep/stepProgress/toggleStep/开始烹饪』在 Recipes/ 无命中。蓝图 screens-recipes.md:25/34-35 与 Swift 映射 :191(cook checklist Set<Int>)要求。
- [MEDIUM] **详情页缺少『加入膳食计划』入口**
  - 影响: 用户无法从菜谱详情把这道菜加入未来 7 天的膳食计划(选日期 → 加入 → 『查看』跳转 MealPlan),需绕到膳食计划页手动添加,断开了「发现菜谱→排进计划」的路径。
  - Flutter: apps/mobile/lib/screens/recipe_detail_screen.dart:122-152 `_addToPlan`(7 天选择器 + `mealPlanProvider.notifier.addEntry` + 『查看』action);:425-435 顶栏 `recipe_add_to_plan_action` 按钮;:935-998 `_PlanDayPickerSheet`。
  - iOS: apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift 工具栏(:48-77)只有收藏 + 编辑/删除菜单,无加入计划按钮;grep『addEntry/MealPlan/加入计划/addToPlan』在 Recipes/ 无命中。蓝图 screens-recipes.md:25/29/36-37/186 要求。
- [MEDIUM] **自定义食谱表单缺少食材/步骤拖拽排序**
  - 影响: 用户在编辑食谱时无法通过拖拽调整食材或步骤的顺序,只能删除后重新添加来重排,编辑体验明显退化。
  - Flutter: apps/mobile/lib/screens/custom_recipe_form_screen.dart:439-444 食材 `ReorderableListView.builder` + `onReorderItem: _reorderIngredient`(:1007);:563-568 步骤 `ReorderableListView.builder` + `_reorderStep`(:1028);拖拽手柄 ReorderableDragStartListener(:456/623)。
  - iOS: apps/ios/FreshPantry/Features/Recipes/CustomRecipeFormView.swift:463-468(食材)与 :537-539(步骤)用普通 `ForEach`,无 `onMove`;grep『onMove/EditButton』在 Recipes/ 无命中。蓝图 Swift 映射 screens-recipes.md:191 明确要求『ingredient/step arrays support drag-reorder via onMove』。
- [MEDIUM] **菜谱卡片缺少食材匹配进度条与『缺 N 件』**
  - 影响: 浏览列表时用户看不到每张卡上的『食材匹配 m/总数』进度条和『缺 N 件』提示,无法在列表层面快速比较哪道菜更接近能做。
  - Flutter: apps/mobile/lib/widgets/recipe_card.dart:205-247 `_RecipeMeta` 的 progressBlock(『食材匹配 m/total』+ 进度条 + 『缺 missing 件』);列表传入 matchedCount 见 recipes_screen.dart:272-278。
  - iOS: apps/ios/FreshPantry/DesignSystem/Components/RecipeCard.swift:69-92 `content` 只有名称/分类 chip/难度·时间,无进度条与缺件提示;:6-7 注释自述『no ingredient-match progress bar … in this phase』。蓝图 screens-recipes.md:153 要求。

## Shopping (6)
- [HIGH] **「一键入库」批量入库 CTA 缺失(勾选已购 → 审核入库 → 移除已应用项)**
  - 影响: 用户无法把已勾选的购物项一次性送入库存。Flutter 在有已购项时底部浮出「已购买的 N 项一键入库」按钮,点开 IntakeReviewScreen 审核(数量解析、批次合并、可逐项取消),应用后仅移除真正入库成功的项。iOS 完全没有这条路径,勾选完只能手动逐条删除,再去库存页重新手输——购物→库存的闭环断裂。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:129-150 底部 FilledButton(key 'shopping_to_intake_cta','已购买的 $checkedCount 项一键入库')→ :269-296 _openIntakeReviewForChecked → controller.buildProposals/seed + push IntakeReviewScreen + controller.removeApplied;apps/mobile/lib/providers/shopping_intake_controller.dart:23-53 buildProposals/removeApplied
  - iOS: 缺失。apps/ios/FreshPantry/Features/Shopping/ShoppingView.swift 全文无任何底部 CTA / IntakeReview 入口;grep 证实 IntakeProposalFactory.fromShoppingItems 与 proposalIdForShoppingItem(apps/ios/FreshPantry/Domain/Proposals/IntakeProposalFactory.swift:40,42,52)仅被测试 ProposalParityTests.swift 引用,ShoppingStore.swift 未调用;ShoppingStore 虽有 checkedCount/uncheckedCount(:165-166)却无人消费。无 plan/spec 标注此为有意移除。
- [MEDIUM] **逐项「加入库存」快捷动作缺失(勾选后 snackbar 的 action)**
  - 影响: Flutter 中点勾选某项后会弹出「『X』已购买」并带「加入库存」按钮,可对单项直接走审核入库流程。iOS 勾选只是切换 checked 状态,没有任何后续动作或提示,用户无法对单项快捷入库。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:244-267 _onItemChecked → showAppSnackBar('「${item.name}」已购买', actionLabel:'加入库存', onAction: _addItemToInventory);:298-321 _addItemToInventory 走 seed proposals + IntakeReviewScreen('加入库存') + removeApplied
  - iOS: 缺失。ShoppingView.swift:97-99 ShoppingRow 的 onToggle 仅 `store.toggleChecked(item)`;ShoppingStore.toggleChecked(:57-72)只翻转状态;Shopping feature 内 grep 无「加入库存」/contextMenu/任何 toggle 后反馈。
- [MEDIUM] **采购进度卡缺失(done/total 大数字 + 百分比 + 进度条)**
  - 影响: Flutter 顶部有渐变进度卡展示「本次采购进度」「done / total 项」「percent%」和进度条,用户一眼可见购物完成度。iOS 只有 NavigationTitle『购物清单』,无任何进度/计数展示,完成度信息完全看不到。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:66-75 + 406-504 _ProgressCard(done/total/progress, percent, 进度条);顶栏 subtitle '$checkedCount/$total 已完成 · $uncheckedCount 件待购' :60-63
  - iOS: 缺失。ShoppingView.swift 仅 `.navigationTitle("购物清单")`(:25);Shopping feature 内 grep『进度/采购/percent/progress』0 命中。ShoppingStore 暴露了 checkedCount/uncheckedCount(:165-166)但视图未渲染。
- [MEDIUM] **待购/已购/全部 筛选 chip 缺失**
  - 影响: Flutter 提供「全部 / 待购买 / 已购」三档 filter chip(含计数),可只看待购或只看已购。iOS 无任何筛选,所有项混排(仅靠已勾选排到底部),清单长时无法聚焦待购项。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:87-96 _FilterChipRow + :506-565;状态 shoppingFilterProvider(apps/mobile/lib/providers/shopping_provider.dart:266-268),filterShoppingGroups(:81-100)
  - iOS: 缺失。Shopping feature 内 grep『待购/已购/全部/filter』除 checkedCount 计算外 0 命中;ShoppingStore 无 filter 状态,displaySections 始终返回全部分组。
- [MEDIUM] **删除项「撤销」缺失**
  - 影响: Flutter 删除购物项后弹「『X』已删除」snackbar 带「撤销」,误删可一键恢复。iOS 滑动删除后无任何提示也无法撤销,误删即永久丢失(同库存详情页已有 undo banner,购物却没有)。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:216-242 _deleteShoppingItem → showAppSnackBar('「${item.name}」已删除', actionLabel:'撤销', onAction: notifier.add(item))
  - iOS: 缺失。ShoppingView.swift:102-108 swipeActions 删除直接 `store.delete(item)`,无 undo;ShoppingStore.delete(:108-128)不返回 undo 句柄。对比 IngredientDetailView.swift:80-105 库存侧有完整 undoBanner,购物侧未实现。
- [LOW] **「清空已完成」批量清理 CTA 缺失(含确认对话框)**
  - 影响: Flutter 在有已购项时列表底部显示「清空已完成 (N)」虚线按钮,点击弹确认对话框后一次性移除所有已勾选项。iOS 只能逐条滑动删除,无批量清理入口。
  - Flutter: apps/mobile/lib/screens/shopping_list_screen.dart:122 onClearChecked → :185-214 _confirmClearChecked(showAppConfirmDialog '清理已购项目' + 逐项 remove + 结果 snackbar);:769-798 _ClearDoneButton '清空已完成 ($count)'
  - iOS: 缺失。Shopping feature 内 grep『清空/清理/已完成』0 命中;ShoppingStore 无 clearChecked 类方法。

## MealPlan（膳食计划） (2)
- [HIGH] **缺料卡:把未完成计划餐缺的食材一键加入购物清单**
  - 影响: 用户在膳食计划页看不到「本周还缺 N 样食材」的提示卡,也无法一键把这些缺料加进购物清单。Flutter 里这是膳食计划→购物的核心闭环;iOS 用户排完一周菜后,必须自己逐个回忆缺什么、手动去购物页一条条添加。
  - Flutter: apps/mobile/lib/screens/meal_plan_screen.dart:26 watch mealPlanMissingIngredientsProvider;:49-56 渲染 _MissingCard;:77-99 _addMissingToShopping 逐项调用 shoppingProvider.addFromSuggestion 并 toast「已加入 N 样食材」;:102-166 _MissingCard 显示「本周还缺 $count 样食材 / 一键加入购物清单」。计算源 apps/mobile/lib/providers/meal_plan_provider.dart:162-200 mealPlanMissingIngredientsProvider(解析每条未完成计划餐的菜谱食材、用 recipeIngredientMatchesInventory 比对库存、去重得出缺料名单)。
  - iOS: apps/ios/FreshPantry/Features/MealPlan/MealPlanView.swift 整屏只有 WeekStrip+dayHeader(添加菜品按钮)+dayBody(菜品行/空态),无任何缺料卡或加购入口。apps/ios/FreshPantry/Features/MealPlan/MealPlanStore.swift 无 missing-ingredients 计算(全文件无 missing/ingredient 逻辑)。grep 'missing|缺料|addFromSuggestion|mealPlan' 覆盖 Features/MealPlan、Features/Shopping、Features/Recipes、Domain 均无对应实现;Shopping 侧也无 addFromSuggestion/suggestion 等价物。docs/swiftui-migration/PLAN.md:87 的 P5⑥ 验收只列出「添加/完成/滑删」,未提缺料加购,blueprint/widgets.md 也未标注此功能被有意移除,判定为缺口而非有意裁剪。
- [MEDIUM] **首页本周计划卡的动态摘要与缺料 badge**
  - 影响: 首页入口卡退化为静态文案「规划这一周吃什么」,不再随数据变化。Flutter 用户在首页一眼可知「本周已排 N 顿 · 今天 M 顿」(无计划时显示「还没安排 — 点这里规划这周吃什么」),并通过「还缺 N 样」橙色 badge 被动发现缺料;iOS 用户进卡片前完全看不到本周排了几顿、今天有没有安排、是否缺料,可发现性下降。
  - Flutter: apps/mobile/lib/widgets/dashboard/weekly_plan_card.dart:21 watch mealPlanWeekSummaryProvider;:24-28 subtitle 三态(还没安排 / 本周已排 N 顿 · 今天 M 顿 / 本周已排 N 顿);:77-80 当 summary.missing>0 显示 _MissingBadge;:92-118 _MissingBadge 渲染「还缺 $count 样」。摘要计算 apps/mobile/lib/providers/meal_plan_provider.dart:213-228 mealPlanWeekSummaryProvider(upcoming/today/missing)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:295-328 MealPlanEntryRow 是纯静态卡:标题「膳食计划」+固定副标题「规划这一周吃什么」,无 store 注入、无 count、无 badge。apps/ios/FreshPantry/Features/Dashboard/DashboardStore.swift 无任何 mealPlan/upcoming/顿/missing 计算(grep 退出码 1)。blueprint/widgets.md:259-261 明确把该动态 subtitle 与 _MissingBadge 列为期望行为,故为退化而非有意移除。

## Auth (登录 + 家庭会话/邀请门户) (5)
- [HIGH] **深链邀请捕获完全缺失(点开邀请链接无反应)**
  - 影响: 用户点击/打开家庭邀请链接(https://api.fresh-pantry.../invite/<token>、com.kunish.freshpantry://invite/<token>、freshpantry://invite/<token>)时,iOS 不会弹出邀请预览或进入加入流程;链接被静默丢弃。用户只能手动复制 token 再粘贴到设置里的加入框,丧失了 Flutter 一键深链入会体验。
  - Flutter: apps/mobile/lib/screens/auth_gate_screen.dart:508 _listenForInviteLinks() 订阅 inviteLinkSourceProvider 的 consumeInitialLink()+incomingLinks;:533 _handleIncomingInviteLink(link) 经 inviteTokenFromInput 解析后 setState 打开 _buildInvitePreview。inviteTokenFromInput 支持三种 URL(apps/mobile/lib/household/invite_token.dart:30-58)。
  - iOS: FreshPantry/App/FreshPantryApp.swift:61-67 onOpenURL 只调用 dependencies.clientProvider.handleOpenURL(url),即 SupabaseClientProvider.swift:68 的 client.auth.handle(url)(仅做 Supabase 会话交换),从不调用 InviteToken.fromInput;代码注释自承 '(e.g. invites in the next slice)'。InviteToken.fromInput(FreshPantry/Sync/InviteToken.swift:76) 已具备三种 URL 解析能力但无人调用。Info.plist(FreshPantry/Support/Info.plist:25-34)仅注册 com.kunish.freshpantry 一个自定义 scheme,未注册 freshpantry 短 scheme,也无 applinks Universal Links。判定:能力存在但未接线,且 onOpenURL 未路由到邀请流程。蓝图 screens-auth.md:205 明确要求该功能为迁移目标(非有意移除)。
- [MEDIUM] **收到的待处理邀请提醒 + 一键接受(acceptInviteById)缺失**
  - 影响: 当家庭所有者按用户邮箱发来定向邀请时,Flutter 会在登录后自动全屏提示「收到家庭邀请」并显示家庭概览,用户可直接「接受邀请」或「稍后处理」。iOS 完全没有这个被动提醒入口,用户即使被邀请也看不到任何提示,只能拿到邀请链接手动加入。HouseholdView 的加入流程仅支持手动粘贴 token/URL,不支持按 inviteId 接受。
  - Flutter: apps/mobile/lib/screens/auth_gate_screen.dart:401 _buildPendingInviteReminder(标题'收到家庭邀请'、_InvitePreviewCard、'接受邀请'/'稍后处理'),:578 _acceptPendingInvite→controller.acceptInviteById(preview.inviteId);控制器 apps/mobile/lib/household/household_session_controller.dart:550 refreshPendingInvites / :623 acceptInviteById / state.pendingInvitePreviews。
  - iOS: grep 确认 FreshPantry/Features/Household/HouseholdSessionStore.swift 与 HouseholdView.swift 均无 loadPendingInvites / acceptInviteById / pendingInvitePreviews 的调用或 UI;仅 FreshPantry/Sync/RemotePantryRepository.swift:381 loadPendingInvites、:414 acceptInviteById 在仓库层存在但未被 Store/View 接入。HouseholdView 仅有按 token 的 acceptInvite(input:)(HouseholdView.swift:199 / HouseholdSessionStore.swift:218)。蓝图 screens-auth.md:7、:205 列为迁移必备(非有意移除)。
- [MEDIUM] **所有者「已发出的待处理邀请」列表与撤销(revoke)缺失**
  - 影响: 家庭所有者在 Flutter 可看到自己已发出、尚未被接受的邀请列表('待处理邀请',显示受邀邮箱/'待接受'),并可逐条撤销。iOS 所有者看不到任何已发邀请,也无法撤销已发出的邀请,只能任其过期。
  - Flutter: blueprint screens-auth.md:165 _PendingInviteRow('待处理邀请' + 关闭 IconButton→onRevoke);apps/mobile/lib/household/household_session_controller.dart:695 revokeInvite / :798 refreshOwnerPendingInvites,state.ownerPendingInvites;模型 apps/mobile/lib/household/household_models.dart:93 OwnerPendingInvite。
  - iOS: FreshPantry/Features/Household/HouseholdView.swift 的 inviteCard(:431-464)只生成邀请链接,无已发邀请列表与撤销按钮;HouseholdSessionStore 无 fetchOwnerPendingInvites/revokeInvite/ownerPendingInvites。仓库层有 FreshPantry/Sync/RemotePantryRepository.swift:438 revokeInvite、:469 fetchOwnerPendingInvites 但无 UI/Store 接线。
- [MEDIUM] **邀请二维码生成与分享缺失**
  - 影响: Flutter 创建邀请后弹出底部 sheet,内含可扫描二维码,可'复制链接'/'分享链接'/'分享二维码(PNG 图片)'。iOS 创建邀请后只展示链接文本 + 系统 ShareLink + 复制按钮,没有二维码,家人无法扫码加入。
  - Flutter: blueprint screens-auth.md:170-172 lib/widgets/settings/invite_result_sheet.dart:QrImageView(data:inviteUrl,size 200) + '复制链接'/'分享链接'/'分享二维码'(渲染 PNG pixelRatio 3,分享 fresh-pantry-invite.png),用 qr_flutter + share_plus。
  - iOS: FreshPantry/Features/Household/HouseholdView.swift:466-499 shareResult 仅展示 URL 文本 + ShareLink(item:url) + UIPasteboard 复制,无二维码。全仓 grep 'qrCode/CIQRCode/qrCodeGenerator/CIFilter' 在 FreshPantry/ 下 0 命中。蓝图 screens-auth.md:205 要求用 CoreImage CIFilter.qrCodeGenerator 实现(非有意移除)。
- [MEDIUM] **待处理邀请红点/提醒徽标缺失**
  - 影响: Flutter 有待处理邀请时会在顶栏设置齿轮与设置页「家庭共享」行显示红点提醒用户去处理。iOS 设置页与 Dashboard 均无任何邀请红点/徽标,用户无被动提示得知有未处理邀请。
  - Flutter: docs/superpowers/plans/2026-06-06-household-entry-consolidation.md Task1/Task3:顶栏齿轮 key 'settings_invite_badge'、设置家庭行 key 'household_row_invite_badge',条件 pendingInvitePreviews.isNotEmpty;blueprint screens-auth.md:45 _LinkRow showBadge=pendingInvitePreviews.isNotEmpty。
  - iOS: grep 'badge/Badge/pendingInvite/hasInvite' 于 FreshPantry/Features/Settings/ 与 Dashboard/ 仅命中无关的 SF Symbol(SettingsView.swift:100 person.crop.circle.badge.xmark、:289 bell.badge.fill、DashboardView.swift:385 cart.badge.plus),无邀请红点逻辑。该红点依赖待处理邀请数据,而 iOS 根本未拉取 pendingInvites(见上一条)。

## Inventory (9)
- [MEDIUM] **多选模式(长按进入 → 批量删除 / 批量加入购物清单)缺失**
  - 影响: 用户无法长按进入多选、一次性删除或一次性把多件食材加入购物清单,只能逐个进详情删除,批量整理成本陡增。
  - Flutter: inventory_screen.dart:40 _selected 多选集合、:439 onLongPress 进入多选、_SelectionTopBar(:509)含删除/加购/合并、:132 _deleteSelected(带 outcome sheet+撤销)、:182 _addSelectedToShoppingList;inventory_provider.dart:358 removeMany
  - iOS: InventoryView.swift listBody(:150-164)每行仅 Button{selectedIngredient=item} 推详情,无 onLongPress/EditMode/选择集;InventoryStore.swift 无任何选择状态或批量删除 API;grep selection/longPress 在 Features/Inventory 无命中。PLAN.md 未提及。
- [MEDIUM] **合并批次(合并 N 批)缺失**
  - 影响: 同名同单位同存储的多条批次记录无法被用户手动合并为一条,库存列表会长期堆叠重复行,无法清理。
  - Flutter: inventory_screen.dart:92 _mergeSelected、:55 _canMerge、_SelectionTopBar 合并按钮(:555-577);inventory_provider.dart:673 InventoryNotifier.mergeBatch(求和数量+取较早到期)
  - iOS: grep `merge`/`mergeBatch`/`合并` 在 apps/ios 仅命中 Intake 提案的 mergeInto(ProposalActionChip/IntakeReviewView,属入库审核流,非库存行手动合并)与 RecipesStore.merge;InventoryStore.swift 无 mergeBatch。注:列表加载有自动 consolidation 不在本仓库 Swift 侧呈现为用户手动操作。
- [MEDIUM] **分类筛选 chip(全部 / 不新鲜 / 5 大类)缺失**
  - 影响: 用户在库存页只能按存储位置筛选,无法按食材分类或「不新鲜」筛选,无法快速定位某类或所有临期食材。
  - Flutter: inventory_screen.dart:379 _CategoryChipRow、:675 _inventoryFilterOptions(全部+不新鲜+FoodCategories.values 各带计数);inventory_provider.dart:39 inventoryItemsForCategory、:924 selectedCategoryProvider、:939 filteredByCategoryProvider
  - iOS: InventoryView.swift 仅渲染 storageChips(:117-136,全部+IconType 存储区);InventoryStore.swift StorageFilter 只有 .all/.area,无分类维度;displayItems(:181)只做 storage→search→sort,无 category 过滤;grep 不新鲜/categoryFilter 在 Features/Inventory 无库存筛选命中。
- [MEDIUM] **清空全部食材(顶栏一键清空 + 确认弹窗)缺失**
  - 影响: 用户无法一键清空整个库存,只能逐条删除;重置/重新开始的场景缺失该入口。
  - Flutter: inventory_screen.dart:356 顶栏 delete_sweep 按钮(key inventory_clear_all_button)、:211 _clearAllIngredients(showAppConfirmDialog 确认);inventory_provider.dart:322 InventoryNotifier.clearAll
  - iOS: InventoryView.swift 顶栏仅 plus 添加按钮(:30-37),无 clear-all;InventoryStore.swift 无 clearAll;grep 清空/clearAll/deleteAll 在 apps/ios 仅命中草稿/数组 removeAll 与订阅清理,无库存清空。
- [MEDIUM] **临期屏逐项操作(用了 / 加购)与点击进详情缺失**
  - 影响: 在临期提醒页,用户无法对每条临期食材就地「标记用了(扣减+撤销)」或「加入购物清单」,也无法点行进入详情;该页退化为纯静态展示,失去处理临期食材的主要操作面。
  - Flutter: expiring_screen.dart:325 _MiniBtn「用了」→ _markUsed(:345 remove+撤销)、:332「加购」→ _addToShopping(:375)、:264 行 GestureDetector 推 IngredientDetailScreen
  - iOS: ExpiringView.swift tierList(:69-92)每行只是 FkCard{IngredientRow},无 Button/navigationDestination/onTapGesture/swipeActions;grep 用了/加购/markUsed/navigationDestination 在 ExpiringView.swift 全 0 命中。行不可点、无内联操作。
- [MEDIUM] **食材详情页「加入清单」操作按钮缺失**
  - 影响: 用户在某食材详情页无法把它加入购物清单,需退出到列表另寻入口;详情页的核心动作之一丢失。
  - Flutter: ingredient_detail_screen.dart:262 _ActionRow(onAddToShopping)、:787 _ActionRow 渲染「加入清单」按钮、:91 _addToShoppingList(shoppingProvider.addFromIngredient)
  - iOS: IngredientDetailView.swift body(:24-72)只有 hero/数量新鲜度/OFF详情/信息列表,工具栏仅删除;无任何 add-to-shopping;grep 加入清单/addFromIngredient 在 detail 无命中(仅 LowStockView 有 sticky CTA)。
- [MEDIUM] **添加食材表单的「常购食材」快填 chip 缺失**
  - 影响: 用户添加食材时,Flutter 顶部展示常买项(买过≥2次)chip,一点即填好名称/分类/存储/单位/保质期;iOS 缺该捷径,常买食材每次都要从空白手填。
  - Flutter: add_ingredient_screen.dart:591 _FrequentItemsSection、:703 _applyFrequentItem(一键填充表单)、:1310 frequentItemsProvider;inventory_provider.dart:969 frequentItemsProvider(count>=2 取前6)
  - iOS: AddIngredientForm/AddIngredientView.swift 无 frequent/常购 字段(grep 在 AddIngredientForm.swift 0 命中);FrequentItem 在 apps/ios 仅被 Dashboard 与 LowStock 使用,从未进入添加表单。
- [LOW] **库存卡片上的「加购」(非新鲜食材就地补货)缺失**
  - 影响: 在库存网格里,临期/过期食材卡片上 Flutter 直接显示「加购」按钮可一键补货,iOS 卡片无任何就地动作,补货需多步跳转。
  - Flutter: ingredient_card.dart:141 onBuyAgain!=null && !isFresh 渲染「加购」按钮;inventory_screen.dart:472 onBuyAgain:_addToShoppingList(item)
  - iOS: IngredientRow.swift(DesignSystem/Components)为只读行:avatar+名称+数量+存储 chip+UrgencyBadge+到期标签,注释明确 Read-only(:4);无 onBuyAgain/加购;InventoryView 行也未注入任何补货回调。
- [LOW] **库存页底部「补货 N 项」低库存 CTA 缺失**
  - 影响: Flutter 在库存页有低库存项时,底部钉一条「补货 N 项」按钮可一键把常买缺货项批量加入购物清单;iOS 库存页无此提醒/入口(仅 Dashboard 有低库存入口卡跳转 LowStockView)。
  - Flutter: inventory_screen.dart:486 showLowStockCta、:493 FilledButton.icon「补货 N 项」(key inventory_low_stock_cta)→ runBulkLowStockAdd;lowStockItemsProvider(inventory_provider.dart:975)
  - iOS: InventoryView.swift 无 overlay/底部 CTA、未引用 LowStockStore/lowStock;低库存只在 DashboardView(:371 入口卡)与独立 LowStockView 呈现。库存 tab 内不再有该一键补货提醒。

## Waste(减废成效 / 减废统计) (1)
- [MEDIUM] **首页减废入口卡丢失动态统计 subtitle 与「抢救 N」徽章**
  - 影响: 用户在首页一眼看不到「本月用掉 N · 浪费 M」(或零浪费时的「本月用掉 N 样 · 零浪费 👏」)以及当月抢救临期数(「抢救 N」徽章);iOS 卡片只显示固定文案「看看你的食材用掉率」,必须点进去才能看到任何数字,首页的成效反馈被削弱。
  - Flutter: apps/mobile/lib/widgets/dashboard/waste_insights_card.dart:20-25 watch foodLogMonthStatsProvider 并生成 subtitle(wasted==0 ? '本月用掉 ${consumed} 样 · 零浪费 👏' : '本月用掉 ${consumed} · 浪费 ${wasted}');:62-70 渲染 subtitle;:74-77 stats.rescued>0 时渲染 _RescuedBadge('抢救 $count');_RescuedBadge 定义于 :89-112。蓝图 docs/swiftui-migration/blueprint/widgets.md:255 明确要求该卡含动态 subtitle 与 _RescuedBadge。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:334-367 WasteInsightsEntryRow 为纯静态卡::352-354 写死 Text("看看你的食材用掉率"),不读取任何 FoodLogStats/月度 provider,无 subtitle 计算、无 rescued 徽章。整个 Waste 域无任何「月度 stats 喂给首页卡」的代码路径(grep foodLogMonthStats / 抢救 N 在 Dashboard 下无命中)。属实现偏离蓝图,非有意移除。

## Dashboard（首页） (7)
- [MEDIUM] **「该用了」临期卡一键加入购物清单缺失**
  - 影响: Flutter 首页临期区是横滑卡片,点任一卡片即把该食材加入购物清单并弹出去重提示(已加入/已在清单中);iOS 把临期预览退化为只读行,点不动,用户无法从首页直接把临期食材补进购物清单。
  - Flutter: apps/mobile/lib/screens/dashboard_screen.dart:219-222 `_ExpiringCard(onAdd: () => _addToShoppingList(...))`,卡片为 GestureDetector(onTap: onAdd)(:584-585);_addToShoppingList(:115-133) 调 shoppingProvider.addFromIngredient 并按 added 弹不同 snackbar。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:258-265 临期预览为 `FkCard { IngredientRow(...) }`,FkCard 无 onTap/Button 包裹;IngredientRow(apps/ios/FreshPantry/DesignSystem/Components/IngredientRow.swift:6-44) 为只读、无加购操作;grep `addFromIngredient` 0 命中。
- [MEDIUM] **「今日推荐」今日菜谱卡缺失(含骨架屏)**
  - 影响: 用户在首页看不到智能推荐的今日菜谱 banner(带匹配食材数、点进菜谱详情),也没有加载中的骨架屏占位;首页少了一个核心的「今天做什么菜」入口。
  - Flutter: apps/mobile/lib/screens/dashboard_screen.dart:274-337 _TodayRecommendationSection:watch recommendedRecipesProvider,渲染 RecipeCard(banner) + matchedIngredientCount,点击 push RecipeDetailScreen;加载态渲染 3 张 FkRecipeSkeletonCard(:283-296);属 Stage3 计划明确保留的功能(docs/superpowers/plans/2026-05-15-stage3-decision-aids.md:12 提到与「今日推荐」并存)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardContent.body(DashboardView.swift:113-145) 的 VStack 无推荐菜谱区;DashboardStore 无 recipe 依赖(DashboardStore.swift:19-22);grep 首页文件「今日推荐/recommend/智能推荐」0 命中。未在 plans 中标记从首页移除。
- [MEDIUM] **「用临期食材」兜底菜谱卡(ExpiringFallbackCard)缺失**
  - 影响: 用户在首页看不到「用你的临期食材今天就能做」的兜底菜谱卡(按最大临期覆盖排序,显示可用 N 件临期食材及前 3 个食材名 chip,点进 useExpiring 详情),失去一个针对性减废建议入口。
  - Flutter: apps/mobile/lib/screens/dashboard_screen.dart:68 挂载 `ExpiringFallbackCard()`;组件 apps/mobile/lib/widgets/dashboard/expiring_fallback_card.dart:13-126 watch expiringFallbackRecipeProvider,展示「可用 N 件临期食材」+ covered chips,点击 push RecipeDetailScreen(useExpiring:true)。该卡为 Stage3 计划专门设计(docs/superpowers/plans/2026-05-15-stage3-decision-aids.md:12,:736)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/* 无对应视图;grep 首页文件「Fallback/用临期/临期食材(作为菜谱)」仅命中临期空态文案,无兜底菜谱卡;DashboardStore 无 recipe 依赖。未在 plans 中标记移除。
- [MEDIUM] **「食材分类」4 列分类网格缺失**
  - 影响: 用户在首页看不到按分类聚合的网格(各分类图标 + 规范分类名 + 件数,最多 8 格);更重要的是失去了「点某分类 → 跳到冰箱 tab 并预置该分类筛选(同时清空 storage 筛选)」这个快捷下钻入口,也没有「还没有分类数据」空态。
  - Flutter: apps/mobile/lib/screens/dashboard_screen.dart:232-272 _CategorySection + :644-719 _CategoryGrid;onTap 内 :260-265 设置 selectedCategoryProvider 并清空 selectedStorageProvider 后 navigateToTab(FkTab.fridge);空态 :251-256 _DashboardEmptyState「还没有分类数据」。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/* 与全工程 grep「食材分类/CategoryGrid/CategorySection」0 命中;DashboardContent 的 VStack(DashboardView.swift:114-141) 无分类网格区。未在 plans 中标记移除。
- [MEDIUM] **减废成效卡数据化副标题与「抢救 N」角标退化**
  - 影响: Flutter 减废卡显示本月实际成效(本月用掉 N 样 · 零浪费 / 本月用掉 N · 浪费 M)及「抢救 N」临期抢救角标;iOS 退化为固定文案「看看你的食材用掉率」,且无条件常显(Flutter 仅有数据时显示),用户在首页看不到本月真实用掉/浪费/抢救数字。
  - Flutter: apps/mobile/lib/widgets/dashboard/waste_insights_card.dart:20-25 按 foodLogMonthStatsProvider 生成 subtitle;:21 `if (stats.isEmpty) return SizedBox.shrink()`(无数据隐藏);:74-77 stats.rescued>0 渲染 _RescuedBadge「抢救 N」(:102-104)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:334-367 WasteInsightsEntryRow 副标题硬编码 `Text("看看你的食材用掉率")`,无 badge、无空态隐藏(DashboardContent 无条件渲染,DashboardView.swift:125);DashboardStore 无 foodLog 依赖,grep 全工程「本月用掉/抢救/rescued(在首页)」0 命中。
- [MEDIUM] **库存不足卡内联预览与一键全部加购退化**
  - 影响: Flutter 首页库存不足卡内联展示前 4 项常买缺货(图标+名称+已买次数)+「+还有 N 项」,并提供「全部加入购物清单 (N)」按钮(带确认弹窗、批量加购、去重计数 toast),用户无需进二级页即可一键补货;iOS 退化为一张只带数量副标题的导航卡,必须先点进 LowStockView 才能加购。
  - Flutter: apps/mobile/lib/widgets/dashboard/low_stock_card.dart:46 展示 items.take(4) 行(_LowStockRow :107-136),:47-57「+还有 N 项」,:59-67 FilledButton「全部加入购物清单」→ runBulkLowStockAdd(:77-105:确认弹窗+批量 addFromSuggestion+toast)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:374-409 LowStockEntryRow 仅一行「N 项常买缺货」+chevron,无内联条目、无加购按钮。批量加购能力存在但已移到下钻页 apps/ios/FreshPantry/Features/Inventory/LowStockView.swift:208-228(sticky CTA),首页本身的内联一键加购 affordance 丢失。
- [LOW] **本周计划卡数据化副标题与「还缺 N 样」角标退化**
  - 影响: Flutter 膳食计划卡会显示真实进度(本周已排 N 顿 · 今天 M 顿 / 还没安排提示)以及缺料角标「还缺 N 样」;iOS 退化为固定文案「规划这一周吃什么」,用户在首页看不到本周已排几顿、今天几顿、还差几样食材。
  - Flutter: apps/mobile/lib/widgets/dashboard/weekly_plan_card.dart:21-28 按 mealPlanWeekSummaryProvider 生成 subtitle(本周已排/今天);:77-80 当 summary.missing>0 渲染 _MissingBadge「还缺 N 样」(:108-110)。
  - iOS: apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift:295-328 MealPlanEntryRow 副标题硬编码 `Text("规划这一周吃什么")`,无 badge;DashboardStore 无 mealPlan 依赖(grep DashboardStore.swift「mealPlan」0 命中),grep 全工程「本周已排/还缺」0 命中。

## Settings (3)
- [MEDIUM] **AI「测试连接」按钮与结果反馈缺失**
  - 影响: 用户在 AI 设置里无法在保存前验证 Base URL/API Key/Model 是否可用,也看不到「连接成功」或具体错误(401/网络/模型不存在)文案;只能盲存后到实际功能里才发现配置错误。
  - Flutter: apps/mobile/lib/screens/ai_settings_screen.dart:152-171 OutlinedButton(key 'ai_test_connection','测试连接')→_runTest;:101-113 _runTest 调 defaultTestConnection;:19-37 defaultTestConnection 用 AiClient.chat 发 'reply with: ok' 探测并返回 ConnectionTestResult.ok/error
  - iOS: apps/ios/FreshPantry/Features/Settings/AiSettingsView.swift:8 注释明写『The live connection-test probe is OUT OF SCOPE for this slice (AI feature phase)』,body(:29-61) 只有状态行+四个字段+保存,无测试按钮。但 iOS 的 AI 功能已落地(apps/ios/FreshPantry/Services/AiClient.swift 存在 chat/completions 实现),且迁移蓝图 docs/swiftui-migration/blueprint/screens-auth.md:198 与末尾『AI test probe: a ConnectionTester protocol (injectable)...』明确要求实现此探测,故属未做完而非有意移除。
- [MEDIUM] **「饮食偏好」7 个预设标签(家庭品类偏好)整段缺失**
  - 影响: 用户无法在设置里勾选 高蛋白/低脂/素食/家常菜/快手菜/儿童餐/低碳水 这 7 个口味偏好来影响菜谱推荐;该能力在 iOS 设置页完全不存在。
  - Flutter: apps/mobile/lib/screens/settings_screen.dart:358-415 SECTION '饮食偏好',Wrap 渲染 7 个 _PrefChip(高蛋白/低脂/素食/家常菜/快手菜/儿童餐/低碳水),点击 toggle 后调 householdSessionControllerProvider.notifier.updateCategoryPreferences(household.id,newPrefs);选中态来自 household.categoryPreferences
  - iOS: apps/ios/FreshPantry/Features/Settings/SettingsView.swift body(:43-56) 只有 account/reminder/dietary(忌口)/assistant/comingSoon/about 六段,无饮食偏好段;全仓搜索 7 个标签字符串仅命中菜谱数据 howtocook.json,无 UI。注意:iOS dietarySection(:166-175)是『忌口关键字编辑器』,对应 Flutter 菜谱页的 _DietaryExclusionsSheet(recipes_screen.dart:720),与本『品类偏好 chips』是两个不同功能,不能互相顶替。底层模型 HouseholdModels.swift:22 与 RemotePantryRepository.swift:357 已具备 categoryPreferences 字段与 updateCategoryPreferences,但无任何设置 UI 调用。蓝图 docs/swiftui-migration/blueprint/screens-auth.md:54 明确要求保留此段,故非有意移除。
- [LOW] **3 项统计卡(食材/采购/收藏菜谱数量)缺失**
  - 影响: 用户在设置页看不到当前库存数、采购清单数、收藏/自建菜谱数的概览。
  - Flutter: apps/mobile/lib/screens/settings_screen.dart:229-238 _StatRow items=[('食材',inventoryCount),('采购',shoppingCount),('收藏菜谱',recipeCount)];计数来自 :172-180 watch inventoryProvider/shoppingProvider/customRecipesProvider 的 length
  - iOS: apps/ios/FreshPantry/Features/Settings/SettingsView.swift body(:43-56) 无统计卡/计数展示;accountSection(:60-86)仅账号与家庭两个 NavigationLink,无 3-stat grid。蓝图 docs/swiftui-migration/blueprint/screens-auth.md:41 仍列出 inventoryCount/shoppingCount/recipeCount,未注明移除。

## Household (4)
- [MEDIUM] **Owner 「待处理邀请」列表 + 撤销邀请**
  - 影响: 家庭拥有者看不到自己已发出、对方尚未接受的邀请,也无法撤销这些邀请(例如发错邮箱/不想再让某人加入时无法收回),只能任其到期。
  - Flutter: household_section.dart:163-180 渲染 '待处理邀请' 区块 + _PendingInviteRow(363-408,含 close 撤销按钮);household_screen.dart:129-146 _onRevokeInvite(撤销确认弹窗 '撤销邀请'/'确定撤销该邀请？')→ controller.revokeInvite;household_session_controller.dart:695-706 revokeInvite + 798-812 refreshOwnerPendingInvites;状态字段 ownerPendingInvites(household_session_controller.dart:313)。
  - iOS: Repository 已实现但无人调用(孤儿):RemotePantryRepository.swift:438 revokeInvite、:469 fetchOwnerPendingInvites。HouseholdSessionStore.swift 无 ownerPendingInvites 状态、无 refreshOwnerPendingInvites/revokeInvite 方法;HouseholdView.swift 的 ActiveHouseholdSection 完全不渲染待处理邀请、无撤销入口。grep 全 apps/ios 仅命中声明处,无任何调用方。blueprint(docs/swiftui-migration/blueprint/screens-auth.md:14,205)明确列为应对等功能,非有意移除。
- [MEDIUM] **已加入用户的「收到的邀请」内联接受 + 入口红点**
  - 影响: 已经在某个家庭里的用户,收到加入另一个家庭的邀请时,iOS 上看不到任何提示/列表,也没有一键 '接受' 按钮;Settings 家庭行也没有红点提醒。用户只能改走手动粘贴 token 的 onboard 流程(且该流程仅在未加入任何家庭时才出现),实际等于无法发现并接受新邀请。
  - Flutter: household_section.dart:136-151 '收到的邀请' 区块 + _IncomingInviteRow(410-448,'接受' FilledButton);household_screen.dart:255-258 incomingInvites=session.pendingInvitePreviews / onAcceptInvite→acceptInviteById;household_session_controller.dart:623-673 acceptInviteById、:550-580 refreshPendingInvites;Settings 入口红点 showBadge=pendingInvitePreviews.isNotEmpty(blueprint screens-auth.md:45 / 2026-06-06-household-entry-consolidation.md:492,528-529)。
  - iOS: Repository 已实现但无人调用(孤儿):RemotePantryRepository.swift:381 loadPendingInvites、:414 acceptInviteById。HouseholdSessionStore.swift 无 pendingInvitePreviews 状态、无 refreshPendingInvites/acceptInviteById 方法。HouseholdView.swift 加入流程(OnboardHouseholdSection:179-207)仅在 selectedHousehold==nil(未加入家庭)时出现,且只支持手动粘贴 token,无 incoming-invite 列表。SettingsView.swift:73-79 家庭行无 badge/红点。RootView/LoginView 无任何 pending-invite reminder。blueprint screens-auth.md:14,205 列为对等功能。
- [MEDIUM] **邀请结果二维码(展示 + 分享二维码)**
  - 影响: 创建邀请后,iOS 只给出可复制/可分享的文本链接,没有二维码;家人无法当面扫码加入,也无法 '分享二维码' 图片。
  - Flutter: invite_result_sheet.dart:80-96 QrImageView(二维码展示)、:133-141 '分享二维码' 按钮、:168-199 _shareQrCode(把二维码渲染成 PNG 分享)。
  - iOS: HouseholdView.swift:466-499 shareResult 仅渲染链接文本 + ShareLink + 复制按钮,无二维码。grep 全 apps/ios 无 CIFilter/qrCodeGenerator/QRCode 等任何二维码生成(InviteToken.swift:24,227 的 'QR' 只是注释/字母表巧合)。blueprint(screens-auth.md:172,205)明确要求用 CoreImage CIFilter.qrCodeGenerator 实现,非有意移除。
- [LOW] **邀请深链接捕获(扫码/点链接直接进入预览)**
  - 影响: 用户点击别人分享的邀请链接(或扫码后打开 App)时,iOS 不会自动捕获 token 并弹出邀请预览/接受;必须手动复制链接再粘贴到加入框。Flutter 支持点链接即进入邀请预览。
  - Flutter: invite_link_service.dart:10-24 AppLinksInviteLinkSource(incomingLinks/consumeInitialLink);invite_link_provider.dart:5-7 inviteLinkSourceProvider;blueprint screens-auth.md:17,178 描述 AuthGateScreen 通过 inviteLinkSourceProvider 捕获入站邀请 URL 并 _handleIncomingInviteLink。
  - iOS: FreshPantryApp.swift:61-67 onOpenURL 仅把 URL 转交 clientProvider.handleOpenURL(auth callback),注释 'invites in the next slice' 表明邀请深链接未实现;grep 全 apps/ios 无 InviteLinkSource/incomingLinks/consumeInitialLink 任何对应物。blueprint screens-auth.md:205 要求 'Handle inbound links via onOpenURL / Universal Links',属计划内对等功能。

## CrossCutting (3)
- [MEDIUM] **全局搜索浮层缺失(跨库存+购物+联网食材百科+搜索历史)**
  - 影响: 用户无法从任意页面唤起一个全局搜索:Flutter 里点顶栏放大镜可一次搜出库存食材、购物清单条目、以及联网查询的「食材百科」(含图片/营养摘要),并保留最近 10 条搜索历史(可单条删除/全部清除)、点击结果直达对应 tab 或食材详情。iOS 只有库存/食谱/膳食计划各自页面内、仅按名称过滤本域条目的搜索框——既没有跨域聚合搜索入口,也没有食材百科联网查询,更没有搜索历史。
  - Flutter: apps/mobile/lib/widgets/common/search_overlay.dart:27 SearchOverlay(整页模糊浮层:_SearchHistoryPanel 历史面板 search_overlay.dart:270 + _SearchResultsPanel 分组结果 search_overlay.dart:382,含库存/购物/食材百科三段);入口在 apps/mobile/lib/widgets/common/top_app_bar.dart:93-99 搜索 IconButton→searchActiveProvider=true;挂载于 apps/mobile/lib/app.dart:188 `if (isSearchActive) const SearchOverlay()`;数据源 apps/mobile/lib/providers/search_provider.dart:21 filteredInventoryProvider、:34 filteredShoppingProvider、:54 searchFoodDetailsProvider(联网食材百科)、:82 SearchHistoryNotifier(最多 10 条,add/remove/clear)
  - iOS: apps/ios 全仓 grep 无 SearchOverlay/searchActive/searchHistory/searchFoodDetails/全局搜索 store;仅有按域名称过滤的 FkSearchField:apps/ios/FreshPantry/Features/Inventory/InventoryView.swift:95 + InventoryStore.swift:34 searchQuery(:182-184 仅 storage 过滤 + 名称匹配,无购物/百科/历史)、RecipesView.swift:161、MealPlanView.swift:382。无任何顶栏搜索入口(DashboardView.swift:34 仅 navigationTitle,无 search 按钮)。blueprint(docs/swiftui-migration/blueprint/widgets.md:275-279)明列 SearchOverlay 应移植为『a search sheet/overlay with sectioned List + debounced query + history』,未标注有意移除——属未完成移植
- [MEDIUM] **系统分享 intent 导入食谱缺失(从其他 App 分享懒饭/下厨房链接进 App)**
  - 影响: 用户无法像 Flutter 那样:在懒饭/下厨房等 App 里点『分享到 食材管家』,App 自动跳首页并打开新建食谱表单、预填该 URL 触发 AI 导入。iOS 既没有 Share Extension,onOpenURL 也只处理鉴权回调,所以从外部 App 分享食谱链接这条入口完全没有(只剩在表单内手动靠剪贴板探测一种途径)。
  - Flutter: apps/mobile/lib/app.dart:112-134 _AppShellState 监听 systemShareSourceProvider:initState consumeInitialText + incomingTextStream.listen→_handleSharedText,extractUrl 命中支持站点后 navigationProvider=0 并 push CustomRecipeFormScreen(prefilledUrl:url);来源 apps/mobile/lib/services/share_intent_service.dart:111 ReceiveSharingIntentSource(getMediaStream/getInitialMedia)、:22 kSupportedRecipeHosts={lanfanapp.com,xiachufang.com}
  - iOS: apps/ios 无 Share Extension target(find 无 *ShareExtension*/ShareViewController,Info.plist 无 NSExtension);Info.plist:25-37 CFBundleURLTypes 仅注册鉴权 scheme com.kunish.freshpantry,无食谱站点 UTI/URL 激活;FreshPantryApp.swift:61-67 onOpenURL 仅 dependencies.clientProvider.handleOpenURL(url) 处理 auth 回调。仅移植了剪贴板那一半:ClipboardRecipeURLDetector.swift,被 CustomRecipeFormView.swift:712 peek() 使用。blueprint(docs/swiftui-migration/blueprint/services.md:120,185)明确要求 share_intent 移植为『Swift Share Extension feeding a shared App Group + AsyncStream from onOpenURL』,未实现且未见有意移除说明
- [MEDIUM] **离线 / 待同步状态横幅缺失(SyncStatusBanner)**
  - 影响: 用户在离线或有未推送改动时看不到任何状态提示:Flutter 顶部会显示一条细横幅『同步中 · N 条待同步』『离线 · N 条待同步』或『离线』,联网/清空后自动收起。iOS 无连通性监测、也无该横幅,用户对『当前离线』『还有 N 条改动没同步上去』毫无可见反馈。
  - Flutter: apps/mobile/lib/widgets/common/sync_status_banner.dart:12 SyncStatusBanner(:19-25 文案分支 同步中/离线±待同步条数,:33 AnimatedSize 展开/收起);apps/mobile/lib/app.dart:182-187 常驻挂载于 Stack 顶;状态源 apps/mobile/lib/providers/sync_status_provider.dart:21 syncStatusProvider(connectivityOnlineProvider + pendingSyncCountProvider,:18 showBanner=!online||pending>0)
  - iOS: apps/ios 全仓 grep 无 SyncStatusBanner、无 connectivity/NWPathMonitor/isOnline 任何连通性监测,无『离线/同步中/待同步』文案;pending 计数(SyncOutboxRepository)仅用于后台推送(FreshPantryApp.swift:86 backgroundTask、RootView.swift:63 回前台 pushPending),从未呈现给用户。blueprint(docs/swiftui-migration/blueprint/widgets.md:287-291)明列其应移植为『a collapsible banner bound to sync state actor』,未实现

## (low, 未复核)
- Inventory: **入库审核行的食材名称内联编辑缺失** — 在入库/AI 解析审核流里,用户无法直接修改某条提案的食材名称(只能改数量/单位/分类/存储/保质期),解析错名只能放弃或回退重来。
- Inventory: **临期屏「提醒已开启」快捷卡(跳转提醒设置)缺失** — Flutter 临期页顶部有「提醒已开启 · 提前1天/每日9:00」卡片,点按直达通知设置;iOS 临期页无此状态展示与快捷入口(设置项本身仍在 SettingsView)。
- Shopping: **分类分组折叠/展开缺失** — Flutter 每个品类组头可点按折叠/展开(带 chevron 旋转动画 + 件数 + 折叠状态跨刷新保留),长清单可收起不关心的品类。iOS 用 List insetGrouped 的普通 Section header,不可点按、不可折叠,品类多时无法收纳。
- Shopping: **添加食材的重复/成功反馈缺失** — Flutter 添加食材后区分反馈:成功『已将「X」加入购物清单』,已存在『「X」已在购物清单中』,让用户知道是否真的加进去了。iOS 添加 sheet 点「添加」后无论成功还是因重名被拒,都直接静默关闭,用户得不到任何确认,重名时以为加成功了实际没加。
- Waste(减废成效 / 减废统计): **「最常浪费」按浪费量排名的洞察缺失(被分类条形图替代)** — Flutter 在该窗口内给出一个按浪费数量降序的「最常浪费」榜单,并对每个分类显示明确的浪费件数(『N 样』,红色),且只列出有浪费的分类;用户能一眼看出「我最常浪费哪一类」。iOS 改为按分类的『用掉 vs 浪费』分组条形图,排序按分类规范顺序(非浪费量),浪费数量需从条形长度目测、无显式数字,故『最常浪费 Top 类』这一排名洞察不再被直接传达。
- Waste(减废成效 / 减废统计): **设置页「减废成效」入口在 iOS 缺失** — Flutter 在设置页『更多』分组提供一个『减废成效』链接(副标题『本月用掉与浪费 · 越用越省』)作为通往减废统计屏的第二个导航路径;iOS 设置页无此入口,少了一条发现/进入减废统计的途径。影响有限,因 iOS 首页减废卡为无条件常驻(DashboardView.swift:125),屏幕始终可达。
- Dashboard（首页）: **时段问候语缺失(早安/午安,主厨。)** — 用户进入首页看不到随时间变化的个性化问候(早安/午安/下午好/晚上好/夜深了,主厨。),首页顶部少了一行人格化文案。
- Dashboard（首页）: **Hero 类别数(· N 类)缺失** — 用户在首页大数字旁看不到食材覆盖多少个分类(Flutter 显示「N 件食材 · M 类」),只剩件数。
- Settings: **家庭共享行缺成员数副标题与待处理邀请红点** — 用户在设置页的『家庭共享』行看不到当前家庭名+成员数(如『家A · 3 名成员』),也看不到有待处理邀请时的红点提示,需进入家庭页才知道有无新邀请。
- Settings: **数据备份导入/导出由剪贴板退化为文件分享/选择** — Flutter 是『复制 JSON 到剪贴板 / 从剪贴板导入』,支持把备份直接贴到 Notes、邮件或聊天里跨设备粘贴恢复;iOS 改为分享文件 / 文件选择器导入,用户若手头是一段已复制到剪贴板的备份 JSON(如他人发来的消息),无法直接粘贴导入,必须先存成 .json 文件。导出也不再有『已复制 N 字节』的即时反馈。
- Auth (登录 + 家庭会话/邀请门户): **邀请预览卡未显示「邀请邮箱」(定向邀请的受邀邮箱)** — Flutter 预览定向邀请时会显示'邀请邮箱:xxx@xxx',让用户确认这封邀请确实发给自己。iOS 的邀请预览卡只显示家庭名、所有者邮箱与四项统计,漏掉受邀邮箱,定向邀请的确认信息退化。