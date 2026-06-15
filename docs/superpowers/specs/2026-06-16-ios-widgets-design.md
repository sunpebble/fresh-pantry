# iOS 系统小组件支持 — 设计文档

- 日期:2026-06-16
- 状态:已确认设计,待写实现计划
- 范围:为 FreshPantry(纯 SwiftUI / iOS 26)新增 WidgetKit 小组件套件

## 1. 目标与决策

为 app 增加桌面/锁屏小组件,在主屏一眼掌握食材与膳食状态,并支持在小组件内直接勾选购物项。

经 brainstorming 确认的产品/架构决策:

- **内容**(四类全要):临期食材提醒、今日膳食计划、购物清单、减废成效。
- **尺寸/位置**(全要):小号、中号(主力)、大号、锁屏配件(circular/rectangular/inline)。
- **交互**:需要可交互按钮(iOS 17+ `AppIntent`),v1 落地购物项勾选。
- **数据共享架构**:**方案 B — App Group + 共享 SwiftData store**(单一数据源,交互写立即落库;接受 store 迁移风险)。
- **深链跳转**:复用现有 `freshpantry://` URL scheme。

## 2. 架构总览

App 与小组件扩展共开**同一个 App Group 容器内的 SwiftData store**。小组件用自己的
`TimelineProvider` 直接查 store 派生展示数据;交互按钮通过 `AppIntent` 直接写 store + 记 sync outbox。

```
┌─ FreshPantry (app) ──────────┐        ┌─ FreshPantryWidgets (extension) ─┐
│ 真实 stores / SyncCoordinator │        │ TimelineProvider → WidgetDataReader│
│ 迁移 store → App Group         │        │ AppIntent(交互) → repo + SyncWriter│
└──────────────┬───────────────┘        └──────────────────┬───────────────┘
               │      ┌─────────────────────────────┐      │
               └──────┤ App Group 共享 SwiftData store ├──────┘
                      │ group.com.kunish.freshPantry   │
                      └─────────────────────────────┘
```

设计原则:小组件扩展只复用既有的持久化/同步源码(零 app 端 churn),不引入与 app 重复的数据逻辑;
所有派生与迁移逻辑做成可用内存容器单测的纯函数/小单元。

## 3. Target / 工程 / 签名

- 新增 `FreshPantryWidgets` app-extension target(`com.apple.widgetkit-extension`),`embed: true` 进主 app。
- **App Group** `group.com.kunish.freshPantry`:主 app 与 widget 各新建 `.entitlements` 文件
  (当前两个 target 都无 entitlements,需新建并在 `project.yml` 挂上 `CODE_SIGN_ENTITLEMENTS`)。
- **共享源码**(关键):widget target 的 `sources` **纳入**(不搬移、零 app churn)以下既有文件:
  - Persistence 的全部 13 个 `@Model` 记录类型(`ModelContainerFactory.models` 列出的全集 —— SwiftData 打开
    store 必须声明完整 schema)。
  - `ModelContainerFactory`。
  - 派生/读取所需的 Domain 模型、枚举、Rules(`Ingredient`、`ShoppingItem`、`FreshnessState`、
    `FoodCategories`、`FoodLogStats` 口径等)。
  - 交互写所需:`SyncWriter`、`SyncOutboxRepository`、相关 repository(至少 `ShoppingRepository`)。
  - 同一份源文件编译进两个 target → schema 必然一致(不引入第二份 `@Model` 定义的漂移风险)。
  - 实现时按编译错误增量补齐传递依赖;widget 不应拉入 UI/网络层。
- ⚠️ **签名 / CI(唯一牵动发布链路的部分)**:
  - App ID 增加 App Groups 能力;重新生成 `FreshPantry App Store` provisioning profile。
  - 新建 `FreshPantry Widgets App Store` profile(含 App Group)。
  - `project.yml` 的 Release 段为 widget target 配置 manual 签名(`Apple Distribution` + 新 profile),
    与主 app/ShareExtension 现有模式一致。
  - CI/TestFlight 流程同步导入新 profile。

## 4. Store 迁移(方案 B 最大风险点)

`ModelContainerFactory` 改为指向 App Group 容器内固定 URL(`<AppGroup>/FreshPantry.store`):

- **App Group URL 解析**:`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`。
- **一次性迁移**:首次发现 App Group store 不存在、而旧默认 store
  (`Application Support/default.store`)存在时,拷贝 `.store` / `.store-shm` / `.store-wal` 三件套到新 URL,
  再从新 URL 打开。拷贝失败则回退旧位置打开,**绝不丢数据**。
- **仅主 app 执行迁移**。widget 端工厂变体:App Group store 文件存在才打开;不存在则返回 nil →
  小组件显示占位/空态(等用户首次启动 app 完成迁移)。widget 永不触发迁移,杜绝竞态。
- 跨进程:SwiftData/SQLite 默认 WAL 支持并发读 + 单写;小组件交互写短暂,冲突概率极低。
  小组件不依赖跨进程变更通知(刷新一律由 app 显式 `reloadAllTimelines()` 或 Provider 定时驱动)。

## 5. 共享数据读取(WidgetDataReader)

widget 扩展内新增 `WidgetDataReader`:开共享只读 `ModelContext`,按 `householdID`(从 App Group
`UserDefaults` 读,见 §7)查询并派生四类内容投影(纯值类型,view-agnostic,内存容器单测):

- **临期**:复用 `DashboardStore` 同款分级/排序口径 →(过期 / 紧急 / 即将)计数 + 最快到期 N 条
  (名称 + 剩余天数 + 档位)。
- **今日膳食**:`MealPlanRecord` 查今天 → 今日菜名列表。
- **购物**:未勾选数 + 前几条名称(供交互行渲染,需带 `id`/`remoteVersion`)。
- **减废**:本月用掉率 + 已省下件数(复用 `WasteInsightsStore` 的 `FoodLogStats` 口径)。

## 6. Widget 结构与尺寸

**一个可配置主力 widget**:`AppIntentConfiguration` + `WidgetContent` 枚举(临期 / 今日膳食 / 购物 / 减废,
默认临期),`supportedFamilies` = `systemSmall / systemMedium / systemLarge`。
**外加锁屏配件 widget**:`accessoryCircular`(临期件数环)、`accessoryRectangular`(可配置内容)、
`accessoryInline`(临期一句话)。布局按 `family × content` 分支渲染。

> 备选(未采纳):拆 4 个独立 widget,gallery 更易发现但布局代码翻倍。采用可配置单 widget 控制范围。

尺寸示意(临期内容):

```
小号               中号                       大号
┌────────┐      ┌──────────────────┐      ┌──────────────────┐
│  ⚠️ 3   │      │ 临期 3 件需处理     │      │ 临期 3 件 · 过期 1   │
│ 即将过期 │      │ • 菠菜   今天到期   │      │ • 菠菜    今天到期   │
│ 过期 1  │      │ • 牛奶   还剩 2 天  │      │ • 牛奶    还剩 2 天   │
└────────┘      │ • 鸡蛋   还剩 3 天  │      │ • 鸡蛋    还剩 3 天   │
                └──────────────────┘      │ • 番茄    还剩 4 天   │
                                          │ ...(6-8 条)         │
                                          └──────────────────┘
```

## 7. 深链跳转 + App Group defaults + 刷新

- **深链**:`.widgetURL()` / `Link` 用 `freshpantry://` 深链(`/inventory`、`/expiring`、`/shopping`、
  `/mealplan`、`/waste`)。`FreshPantryApp.onOpenURL` 增加 `WidgetDeepLinkRouter.capture(url:)`;RootView
  消费后切到对应 tab(复用现有 cross-tab pending-intent 路由模式:`.task(id:)` 读取 + build-once 守卫)。
- **App Group `UserDefaults`**:app 在 `householdID` / `clientId` 变化时写入共享 suite,供 widget 的
  `WidgetDataReader` 与交互 `AppIntent` 读取(`SyncWriter` 需要 household/client 才会记 op)。
- **刷新驱动**:app 在「`syncSession.dataRevision` 变化(RootView 已有 `onChange` 钩子)/ 进后台 /
  关键本地 mutation」后调 `WidgetCenter.shared.reloadAllTimelines()`(收敛进一个 `WidgetRefreshCoordinator`);
  Provider 另设每日跨午夜刷新点,让临期剩余天数每天重算。

## 8. 交互按钮(购物勾选,复用 SyncWriter)

中号/大号「购物清单」widget 每行带勾选按钮 → `ToggleShoppingItemIntent`(`AppIntent`,`perform()`):

1. 开共享容器 → `ShoppingRepository.updateRow(householdID, toggled)` 翻转 `isChecked`;
2. 构造 `SyncWriter(outbox:, coordinator: nil, session: <从 App Group 读 household/client>)`,
   `enqueue(entityType: .shoppingItem, entityId:, operation: .update, patch: ["isChecked": .bool(...)],
   baseVersion: prior.remoteVersion)` —— **只记 outbox 不推送**(coordinator 为 nil);
3. 共享 store 已落库,小组件随 `reloadAllTimelines()` 立即反映;
4. app 下次进前台,现有 `SyncCoordinator` 把这条 op 推到 Supabase;app 内存 store 经既有
   foreground/dataRevision 钩子重读,与小组件收敛。

完整复用既有 `toggleChecked` 写路径(`updateRow` + `SyncWriter.enqueue(.shoppingItem/.update,
patch:["isChecked"], baseVersion: remoteVersion)`),不新增第二套写逻辑。

## 9. 测试策略

- **Store 迁移**:旧 URL 种入记录 → 跑迁移 → 断言新 URL 可读、数据完整;拷贝失败回退旧位置。
- **WidgetDataReader**:内存容器种四类记录,断言临期分级/排序、今日膳食、购物未勾选数+预览、减废用掉率派生正确。
- **ToggleShoppingItemIntent**:对内存容器执行 → 断言 `isChecked` 翻转 + outbox 记录一条 `.shoppingItem/.update`
  且 `baseVersion` 正确。
- **WidgetDeepLinkRouter**:URL → tab 路由解析单测。
- Widget views:以 Preview/快照为主,轻量验证各 family × content 布局不崩。

## 10. 受影响的现有文件(其余皆新增)

- `apps/ios/project.yml` —— 新 target、App Group、widget 共享 sources、Release 签名。
- `Persistence/ModelContainerFactory.swift` —— App Group URL + 一次性迁移 + widget 只读变体。
- `App/FreshPantryApp.swift` / `App/RootView.swift` —— 深链路由消费、`reloadAllTimelines()` 钩子、
  写 App Group defaults。

## 11. 非目标(YAGNI)

- 不做小组件内「加购」「扫码」等额外交互(v1 仅购物勾选)。
- 不拆多个独立 widget kind(采用单可配置 widget)。
- 不引入 widget 专属网络拉取(纯走共享 store,坚持离线优先)。
- 不在本期重构持久化层为独立 framework(用 XcodeGen 同源 target 成员关系即可)。
