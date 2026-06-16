# iOS 系统小组件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 FreshPantry(纯 SwiftUI / iOS 26)新增 WidgetKit 小组件套件——临期/今日膳食/购物/减废四类内容,小/中/大 + 锁屏配件尺寸,并支持在购物清单小组件内直接勾选(iOS 17+ 交互按钮)。

**Architecture:** 新增 `FreshPantryWidgets` app-extension,与主 app 共开同一个 **App Group**(`group.com.kunish.freshPantry`)容器内的 SwiftData store。widget 用 `AppIntentTimelineProvider` 直接查共享 store 派生展示数据;交互按钮通过 `AppIntent` 写 store + 记 sync outbox。widget 扩展只编译既有的**纯持久化/领域源码**(零 app 端 churn,schema 必然一致),不拉入 UI/网络层。

**Tech Stack:** Swift 6(strict concurrency)/ SwiftData(`@Model`、`@ModelActor`)/ WidgetKit(`AppIntentConfiguration`)/ App Intents / App Group / XcodeGen。

---

## 关键设计决策(规划阶段相对 spec 的改良 — 实现前先读)

设计 spec 在 `docs/superpowers/specs/2026-06-16-ios-widgets-design.md`。规划阶段核对真实代码后,确定以下更安全的落地路径:

1. **交互写不经 `SyncWriter`。** spec §8 原写「复用 `SyncWriter(coordinator: nil)`」。但 `SyncWriter` 持有 `SyncCoordinator?` 类型,而 `SyncCoordinator`/`SupabaseSyncGateway`/`RemotePantryRepository` 都 `import Supabase`(网络层)。把 `SyncWriter` 编进 widget 会把整个 Supabase SDK 拖进小组件二进制。**改为:widget 的 `AppIntent` 直接用 `SyncOutboxRepository.enqueue(SyncOperation(...))` 记录 outbox 操作**——语义完全等价(coordinator 本就是 nil → 不推送),只是不经那层 wrapper。app 下次前台用既有 `SyncCoordinator` 推送。
2. **真实操作类型是 `.toggleChecked`(不是 spec §8 写的 `.update`)。** `ShoppingStore.toggleChecked` 实际 enqueue 的是 `operation: .toggleChecked`,`patch: ["isChecked": .bool(...)]`,`baseVersion: prior.remoteVersion`。widget 严格对齐。
3. **共享源码精确边界。** `Domain/` 整目录纯净(仅 `import Foundation`/`CryptoKit`),整目录共享。`Persistence/` 仅 `Repositories/RemoteRecipeCatalog.swift` 碰 Supabase 且无被引用;widget 只纳入 13 个 `@Model` 记录 + `ModelContainerFactory` + 5 个本地 repo,排除 `HouseholdCache`/`RecipeCatalogCache`/`Stores/`/其余 `Repositories/`(避免拖入 Supabase 与 Sync/Household 依赖)。**不共享 `Sync/` 与 `Features/`/`App/`。**
4. **纯减废统计下沉 Domain。** `FoodLogStats` + `computeStats` 当前在 `Features/Waste/WasteInsightsStore.swift`,但该 store 持有 `SyncWriter`(→Supabase)不能整文件共享。抽到 `Domain/Rules/FoodLogStatistics.swift`,两边复用(DRY)。
5. **深链全部走首页 `DashboardRoute`。** 实测临期/今日膳食/减废三屏都是从首页 tab 内 `NavigationStack` push `DashboardRoute.{expiring,mealPlan,wasteInsights}`;购物是独立 tab。新增 `WidgetDeepLinkRouter`(app 端)解析 `freshpantry://` host,RootView 切 tab,DashboardView 消费并 push 路由。
6. **一个 widget kind 承载全部 6 个 family**(systemSmall/Medium/Large + accessoryCircular/Rectangular/Inline),内容用 `AppIntentConfiguration` 可配置。
7. **v1 刷新触发点**:远程合并(`dataRevision`)、进入后台、身份写入时 `reloadAllTimelines()`——**不做逐条本地 mutation 刷新**(widgets 非实时;用户离开 app 才看 widget,后台刷新已覆盖)。

---

## File Structure

**新增(widget-only,`FreshPantryWidgets/` 目录,只编进 widget target):**
- `FreshPantryWidgets/Info.plist` — `NSExtensionPointIdentifier = com.apple.widgetkit-extension`。
- `FreshPantryWidgets/FreshPantryWidgets.entitlements` — App Group。
- `FreshPantryWidgets/FreshPantryWidgetBundle.swift` — `@main WidgetBundle`。
- `FreshPantryWidgets/FreshPantryWidget.swift` — `AppIntentConfiguration` widget + `supportedFamilies`。
- `FreshPantryWidgets/WidgetContentChoice.swift` — `AppEnum` + `SelectWidgetContentIntent`(配置 intent)。
- `FreshPantryWidgets/WidgetProvider.swift` — `AppIntentTimelineProvider` + `WidgetEntry`。
- `FreshPantryWidgets/ToggleShoppingItemIntent.swift` — 交互 intent(薄封装,调用共享 service)。
- `FreshPantryWidgets/WidgetRootView.swift` — `family × content` 分支渲染。
- `FreshPantryWidgets/WidgetContentViews.swift` — 四类内容的 system-family 视图。
- `FreshPantryWidgets/WidgetAccessoryViews.swift` — 锁屏配件视图。

**新增(shared,`FreshPantry/Widgets/Shared/` 目录,app + widget + 测试都编):**
- `FreshPantry/Widgets/Shared/WidgetSharedDefaults.swift` — App Group id/keys + 读写 household/client。
- `FreshPantry/Widgets/Shared/WidgetSnapshots.swift` — 四类内容投影值类型。
- `FreshPantry/Widgets/Shared/WidgetDataReader.swift` — 开共享容器,派生四类投影。
- `FreshPantry/Widgets/Shared/ShoppingToggleService.swift` — 可测的勾选+记 outbox 逻辑。

**新增(app-only,`FreshPantry/Widgets/App/` 目录,只编进 app target):**
- `FreshPantry/Widgets/App/WidgetDeepLinkRouter.swift` — `freshpantry://` host → 目标解析 + pending 态。
- `FreshPantry/Widgets/App/WidgetRefreshCoordinator.swift` — `reloadAllTimelines()` 单一 seam。

**新增(Domain,shared):**
- `Domain/Rules/FoodLogStatistics.swift` — 抽出的 `FoodLogStats` + `computeStats`。

**新增(entitlements):**
- `FreshPantry/Support/FreshPantry.entitlements` — App Group。

**修改:**
- `apps/ios/project.yml` — app target 挂 entitlements + embed widget;新增 widget target(sources/signing)。
- `FreshPantry/Persistence/ModelContainerFactory.swift` — App Group URL + 一次性迁移 + `makeSharedExisting()`。
- `FreshPantry/Features/Waste/WasteInsightsStore.swift` — 移走 `FoodLogStats`/`computeStats`,留转发壳。
- `FreshPantry/App/AppDependencies.swift` — 暴露 `widgetDeepLinkRouter`。
- `FreshPantry/App/FreshPantryApp.swift` — 写 App Group defaults、reload 触发、深链 capture、router 注入环境。
- `FreshPantry/App/RootView.swift` — 消费 `widgetDeepLinkRouter` 切 tab + `dataRevision` reload。
- `FreshPantry/Features/Dashboard/DashboardView.swift` — 消费 `widgetDeepLinkRouter` push `DashboardRoute`。

**测试(`FreshPantryTests/`,依赖 app target 故可见 shared 类型):**
- `FreshPantryTests/Widgets/WidgetSharedDefaultsTests.swift`
- `FreshPantryTests/Widgets/FoodLogStatisticsTests.swift`
- `FreshPantryTests/Widgets/ModelContainerMigrationTests.swift`
- `FreshPantryTests/Widgets/WidgetDataReaderTests.swift`
- `FreshPantryTests/Widgets/ShoppingToggleServiceTests.swift`
- `FreshPantryTests/Widgets/WidgetDeepLinkRouterTests.swift`

---

## 通用命令(每个 build/test 步骤用到)

XcodeGen 工程是 gitignore 的,改完 `project.yml` 必须重新生成。构建/测试在仓库根的 `apps/ios` 下:

```bash
# 重新生成工程(改 project.yml 后)
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && xcodegen generate

# 跑全部单测(模拟器)
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests 2>&1 | tail -40

# 只构建(含 widget target)
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -40
```

> 若机器无 `iPhone 16 Pro` 模拟器,用 `xcrun simctl list devices available` 选一个已装的 iOS 26 设备名替换。

---

### Task 1: Widget 扩展 target + App Group entitlements + 共享源码(XcodeGen)

先把 target 骨架、App Group、共享源码边界落地并 Debug 可构建,后续任务往里填逻辑。

**Files:**
- Create: `apps/ios/FreshPantry/Support/FreshPantry.entitlements`
- Create: `apps/ios/FreshPantryWidgets/FreshPantryWidgets.entitlements`
- Create: `apps/ios/FreshPantryWidgets/Info.plist`
- Create: `apps/ios/FreshPantryWidgets/FreshPantryWidgetBundle.swift`(临时占位 widget)
- Modify: `apps/ios/project.yml`

- [ ] **Step 1: app target 的 App Group entitlements**

Create `apps/ios/FreshPantry/Support/FreshPantry.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.kunish.freshPantry</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: widget target 的 App Group entitlements**

Create `apps/ios/FreshPantryWidgets/FreshPantryWidgets.entitlements`(内容与 Step 1 完全相同):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.kunish.freshPantry</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: widget 扩展 Info.plist**

Create `apps/ios/FreshPantryWidgets/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Fresh Pantry</string>
	<key>CFBundleName</key>
	<string>FreshPantryWidgets</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 4: 临时占位 widget(让 target 可编译)**

Create `apps/ios/FreshPantryWidgets/FreshPantryWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

/// Widget bundle 入口。Task 8-10 会用真实的 `FreshPantryWidget` 替换占位实现。
@main
struct FreshPantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

private struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryPlaceholder", provider: PlaceholderProvider()) { _ in
            Text("Fresh Pantry")
        }
        .supportedFamilies([.systemSmall])
    }
}

private struct PlaceholderEntry: TimelineEntry { let date: Date }

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
```

- [ ] **Step 5: app target 挂 entitlements + embed widget(project.yml)**

在 `apps/ios/project.yml` 的 `FreshPantry` target 的 `settings.base` 中,`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` 后追加一行:

```yaml
        CODE_SIGN_ENTITLEMENTS: FreshPantry/Support/FreshPantry.entitlements
```

并在 `FreshPantry` target 的 `dependencies:` 列表(`- target: ShareExtension` 之后)追加:

```yaml
      - target: FreshPantryWidgets
        embed: true
```

- [ ] **Step 6: 新增 widget target(project.yml)**

在 `apps/ios/project.yml` 的 `targets:` 下,`ShareExtension:` target 块之后插入新 target:

```yaml
  FreshPantryWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      # widget-only 代码
      - path: FreshPantryWidgets
      # shared widget 逻辑(app target 也编它们,测试可见)
      - path: FreshPantry/Widgets/Shared
      # 纯领域层(仅 Foundation/CryptoKit,整目录安全)
      - path: FreshPantry/Domain
      # 持久化层:13 个 @Model 记录 + ModelContainerFactory(Persistence/ 顶层),
      # 排除会拖入 Supabase / Sync-Household 依赖的文件;repos 单独按需纳入。
      - path: FreshPantry/Persistence
        excludes:
          - "HouseholdCache.swift"
          - "RecipeCatalogCache.swift"
          - "Stores/**"
          - "Repositories/**"
      - path: FreshPantry/Persistence/Repositories/ShoppingRepository.swift
      - path: FreshPantry/Persistence/Repositories/InventoryRepository.swift
      - path: FreshPantry/Persistence/Repositories/MealPlanRepository.swift
      - path: FreshPantry/Persistence/Repositories/FoodLogRepository.swift
      - path: FreshPantry/Persistence/Repositories/SyncOutboxRepository.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kunish.freshPantry.Widgets
        PRODUCT_NAME: FreshPantryWidgets
        INFOPLIST_FILE: FreshPantryWidgets/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_ENTITLEMENTS: FreshPantryWidgets/FreshPantryWidgets.entitlements
      configs:
        Debug:
          CODE_SIGN_STYLE: Automatic
        Release:
          CODE_SIGN_STYLE: Manual
          CODE_SIGN_IDENTITY: Apple Distribution
          PROVISIONING_PROFILE_SPECIFIER: FreshPantry Widgets App Store
```

> 注:`FreshPantry/Widgets/Shared` 目录此刻还不存在,XcodeGen 对不存在的源路径会报错。先建一个占位文件保证目录存在:`mkdir -p apps/ios/FreshPantry/Widgets/Shared && printf 'import Foundation\n' > apps/ios/FreshPantry/Widgets/Shared/.keep.swift`(Task 2 会用真实文件,届时删掉 `.keep.swift`)。

- [ ] **Step 7: 创建占位目录、生成工程、Debug 构建**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  mkdir -p FreshPantry/Widgets/Shared && \
  printf 'import Foundation\n' > FreshPantry/Widgets/Shared/Placeholder.swift && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -40
```

Expected: `** BUILD SUCCEEDED **`。两个 target(app + widget)都编译;widget 共享的 Domain/Persistence 源码全部编过。

> **若 widget 报「undefined symbol / cannot find X in scope」**:某个共享文件引用了未纳入 widget 的同模块类型。先确认该类型在 `Domain/` 或已纳入的 5 个 repo 里;若缺,把对应**纯 Foundation/SwiftData** 文件加进 widget 的 `sources`。**绝不**加 `import Supabase`/`import SwiftUI` 的文件——那说明依赖切错了边界,应改设计。

- [ ] **Step 8: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/project.yml apps/ios/FreshPantry/Support/FreshPantry.entitlements \
  apps/ios/FreshPantryWidgets apps/ios/FreshPantry/Widgets && \
  git commit -m "feat(ios): widget 扩展 target + App Group + 共享源码骨架"
```

---

### Task 2: WidgetSharedDefaults(App Group 跨进程身份)

app 把当前 household + clientId 写进 App Group `UserDefaults`,widget 读取以查询作用域 / 构造 outbox 操作。

**Files:**
- Delete: `apps/ios/FreshPantry/Widgets/Shared/Placeholder.swift`(Task 1 占位)
- Create: `apps/ios/FreshPantry/Widgets/Shared/WidgetSharedDefaults.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/WidgetSharedDefaultsTests.swift`

- [ ] **Step 1: 写失败的测试**

Create `apps/ios/FreshPantryTests/Widgets/WidgetSharedDefaultsTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

struct WidgetSharedDefaultsTests {
    /// 用一个独立的内存 suite,避免污染真实 App Group。
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func writeThenReadIdentityRoundTrips() {
        let suite = makeSuite("test.widgetdefaults.roundtrip")
        WidgetSharedDefaults.writeIdentity(householdID: "hh-1", clientID: "cli-9", into: suite)
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "hh-1")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "cli-9")
    }

    @Test func readsEmptyHouseholdWhenUnset() {
        let suite = makeSuite("test.widgetdefaults.empty")
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "")
    }

    @Test func writeOverwritesPrevious() {
        let suite = makeSuite("test.widgetdefaults.overwrite")
        WidgetSharedDefaults.writeIdentity(householdID: "a", clientID: "c1", into: suite)
        WidgetSharedDefaults.writeIdentity(householdID: "b", clientID: "c2", into: suite)
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "b")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "c2")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetSharedDefaultsTests 2>&1 | tail -30
```

Expected: 编译失败(`cannot find 'WidgetSharedDefaults' in scope`)。

- [ ] **Step 3: 实现 WidgetSharedDefaults**

先删占位:`rm apps/ios/FreshPantry/Widgets/Shared/Placeholder.swift`

Create `apps/ios/FreshPantry/Widgets/Shared/WidgetSharedDefaults.swift`:

```swift
import Foundation

/// 主 app 与小组件扩展之间的跨进程身份通道(App Group `UserDefaults`)。
///
/// app 在启动 + 家庭切换时写入当前 household / clientId;widget 的
/// `WidgetDataReader`(查询作用域)与 `ToggleShoppingItemIntent`(构造 outbox
/// 操作的 householdId/clientId)读取它。store 本身走共享 SwiftData 容器;这里
/// 只搬运两个标量身份值。
enum WidgetSharedDefaults {
    /// 主 app 与 widget 共用的 App Group。须与两个 target 的
    /// `.entitlements` 里的 `application-groups` 一致。
    static let appGroupID = "group.com.kunish.freshPantry"

    private static let householdIDKey = "widget.householdID"
    private static let clientIDKey = "widget.clientID"

    /// 共享 suite;App Group 未授权(如本地未签名 dev)时为 nil。
    static var suite: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// 写当前作用域身份。`into` 可注入测试 suite;默认走共享 suite。
    static func writeIdentity(householdID: String, clientID: String, into defaults: UserDefaults? = WidgetSharedDefaults.suite) {
        guard let defaults else { return }
        defaults.set(householdID, forKey: householdIDKey)
        defaults.set(clientID, forKey: clientIDKey)
    }

    static func readHouseholdID(from defaults: UserDefaults? = WidgetSharedDefaults.suite) -> String {
        defaults?.string(forKey: householdIDKey) ?? ""
    }

    static func readClientID(from defaults: UserDefaults? = WidgetSharedDefaults.suite) -> String {
        defaults?.string(forKey: clientIDKey) ?? ""
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetSharedDefaultsTests 2>&1 | tail -30
```

Expected: 3 tests passed。

- [ ] **Step 5: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Widgets/Shared/WidgetSharedDefaults.swift \
  apps/ios/FreshPantryTests/Widgets/WidgetSharedDefaultsTests.swift && \
  git rm --cached apps/ios/FreshPantry/Widgets/Shared/Placeholder.swift 2>/dev/null; \
  git add -A apps/ios/FreshPantry/Widgets && \
  git commit -m "feat(ios): WidgetSharedDefaults 跨进程身份通道"
```

---

### Task 2.5: FoodLogStatistics 下沉 Domain(DRY,供 widget 复用)

把纯减废统计从 `WasteInsightsStore`(持有 `SyncWriter`,不可共享)抽到 Domain。

**Files:**
- Create: `apps/ios/FreshPantry/Domain/Rules/FoodLogStatistics.swift`
- Modify: `apps/ios/FreshPantry/Features/Waste/WasteInsightsStore.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/FoodLogStatisticsTests.swift`

- [ ] **Step 1: 写失败的测试**

Create `apps/ios/FreshPantryTests/Widgets/FoodLogStatisticsTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

struct FoodLogStatisticsTests {
    private func entry(_ outcome: FoodLogOutcome, wasExpiring: Bool = false) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID().uuidString,
            name: "x",
            category: FoodCategories.other,
            outcome: outcome,
            loggedAt: Date(timeIntervalSince1970: 0),
            wasExpiring: wasExpiring,
            remoteVersion: 0
        )
    }

    @Test func talliesConsumedWastedRescuedSaved() {
        let stats = FoodLogStatistics.computeStats([
            entry(.consumed),
            entry(.consumed, wasExpiring: true),
            entry(.wasted),
            entry(.donated),
            entry(.composted),
        ])
        #expect(stats.consumed == 2)
        #expect(stats.wasted == 1)
        #expect(stats.rescued == 1)
        #expect(stats.saved == 2)
        #expect(stats.total == 3)        // consumed + wasted(saved/rescued 不在分母)
        #expect(stats.useUpPercent == 67) // 2/3 = 66.7 → 67
    }

    @Test func emptyIsZero() {
        let stats = FoodLogStatistics.computeStats([])
        #expect(stats.isEmpty)
        #expect(stats.useUpPercent == 0)
    }

    /// 兼容壳:旧 call site / 测试仍可经 WasteInsightsStore 调用,结果一致。
    @Test func wasteStoreWrapperMatches() {
        let entries = [entry(.consumed), entry(.wasted)]
        #expect(WasteInsightsStore.computeStats(entries) == FoodLogStatistics.computeStats(entries))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/FoodLogStatisticsTests 2>&1 | tail -30
```

Expected: 编译失败(`cannot find 'FoodLogStatistics' in scope`)。

- [ ] **Step 3: 创建 Domain 文件(搬移 struct + 纯函数)**

Create `apps/ios/FreshPantry/Domain/Rules/FoodLogStatistics.swift`:

```swift
import Foundation

/// 一个时间窗内的食材去向统计。全是「件数」,绝不汇总数量(数量是自由文本,
/// 故意不求和)。`useUpRate` 是头条指标;`/0` 守卫为 0(尚无去向)。
///
/// 从 `WasteInsightsStore` 抽出,使小组件可在不拖入 `SyncWriter`(网络层)的
/// 前提下复用同一套口径。
struct FoodLogStats: Equatable, Sendable {
    var consumed: Int
    var wasted: Int
    /// Consumed AND already past fresh — "抢救临期" credit.
    var rescued: Int
    /// Donated + composted — positive去向, NOT counted as waste.
    var saved: Int = 0

    static let empty = FoodLogStats(consumed: 0, wasted: 0, rescued: 0, saved: 0)

    /// consumed + wasted(rescued 是 consumed 的子集;saved 是另一种正向去向,
    /// 不进用掉率分母)。
    var total: Int { consumed + wasted }

    /// consumed / (consumed + wasted),无去向时为 0(守卫 /0)。
    var useUpRate: Double { total == 0 ? 0 : Double(consumed) / Double(total) }

    /// 0...100 整数百分比(如 85 → "85% 用掉率")。
    var useUpPercent: Int { Int((useUpRate * 100).rounded()) }

    var isEmpty: Bool { total == 0 }
}

/// 纯聚合(无 SwiftData,可单测)。
enum FoodLogStatistics {
    /// Tallies consumed / wasted / rescued / saved over `entries`. `rescued`
    /// counts a consumed entry whose batch was already expiring (`wasExpiring`).
    static func computeStats(_ entries: [FoodLogEntry]) -> FoodLogStats {
        var consumed = 0
        var wasted = 0
        var rescued = 0
        var saved = 0
        for entry in entries {
            if entry.isConsumed {
                consumed += 1
                if entry.wasExpiring { rescued += 1 }
            } else if entry.outcome.isSaved {
                // 捐了/堆肥 = 非浪费正向去向,绝不计入 wasted。
                saved += 1
            } else {
                wasted += 1
            }
        }
        return FoodLogStats(consumed: consumed, wasted: wasted, rescued: rescued, saved: saved)
    }
}
```

- [ ] **Step 4: 从 WasteInsightsStore 移除重复定义、留转发壳**

在 `apps/ios/FreshPantry/Features/Waste/WasteInsightsStore.swift` 中:

删除 `struct FoodLogStats { ... }` 整块(原 39-61 行,含 `static let empty`/`total`/`useUpRate`/`useUpPercent`/`isEmpty`;`WasteCategoryBreakdown` 保留不动)。

把原 `static func computeStats(_ entries:)`(253-270 行)整块替换为转发壳:

```swift
    /// 转发到 Domain 的 `FoodLogStatistics`(纯口径单一真源)。保留此静态方法,
    /// 既有 call site / 测试无需改动。
    static func computeStats(_ entries: [FoodLogEntry]) -> FoodLogStats {
        FoodLogStatistics.computeStats(entries)
    }
```

`computeCategoryBreakdown` 与 `WasteCategoryBreakdown` 不动。

- [ ] **Step 5: 跑测试确认通过(含回归)**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/FoodLogStatisticsTests 2>&1 | tail -30
```

Expected: 3 tests passed。再跑既有减废测试确保没回归:

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WasteInsightsStoreTests 2>&1 | tail -30
```

Expected: 既有套件依旧全绿(若套件名不同,用 `grep -rl 'WasteInsightsStore' apps/ios/FreshPantryTests` 找实际文件名)。

- [ ] **Step 6: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Domain/Rules/FoodLogStatistics.swift \
  apps/ios/FreshPantry/Features/Waste/WasteInsightsStore.swift \
  apps/ios/FreshPantryTests/Widgets/FoodLogStatisticsTests.swift && \
  git commit -m "refactor(ios): FoodLogStats/computeStats 下沉 Domain 供 widget 复用"
```

---

### Task 3: ModelContainerFactory 迁到 App Group store

把生产 store 迁到 App Group 容器,一次性无损搬迁旧 `default.store`,并提供 widget 用的「仅打开已存在 store」变体。

**Files:**
- Modify: `apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/ModelContainerMigrationTests.swift`

- [ ] **Step 1: 写失败的测试(纯文件迁移函数)**

Create `apps/ios/FreshPantryTests/Widgets/ModelContainerMigrationTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

struct ModelContainerMigrationTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "migtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func copiesStoreTripletToTarget() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store")
        let target = targetDir.appending(path: "FreshPantry.store")
        for suffix in ["", "-shm", "-wal"] {
            try "data\(suffix)".write(to: URL(fileURLWithPath: legacy.path + suffix), atomically: true, encoding: .utf8)
        }

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        for suffix in ["", "-shm", "-wal"] {
            let dst = URL(fileURLWithPath: target.path + suffix)
            #expect(fm.fileExists(atPath: dst.path))
            #expect((try? String(contentsOf: dst, encoding: .utf8)) == "data\(suffix)")
        }
    }

    @Test func noOpWhenTargetAlreadyExists() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store")
        let target = targetDir.appending(path: "FreshPantry.store")
        try "OLD".write(to: legacy, atomically: true, encoding: .utf8)
        try "EXISTING".write(to: target, atomically: true, encoding: .utf8)

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        // 目标已存在 → 绝不覆盖。
        #expect((try? String(contentsOf: target, encoding: .utf8)) == "EXISTING")
    }

    @Test func noOpWhenLegacyMissing() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store") // 不创建
        let target = targetDir.appending(path: "FreshPantry.store")

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        #expect(!fm.fileExists(atPath: target.path))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/ModelContainerMigrationTests 2>&1 | tail -30
```

Expected: 编译失败(`migrateStore` 不存在)。

- [ ] **Step 3: 改写 ModelContainerFactory**

把 `apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift` 中 `makeShared()` 之后整段(到文件末尾的 `makeInMemory` 之前)替换/扩展。完整新内容如下(保留 `models`/`schema`/`makeInMemory` 不变,替换 `makeShared`,新增迁移与 widget 变体):

```swift
    static var schema: Schema { Schema(models) }

    /// 共享 store 的固定文件名(App Group 容器内)。
    static let storeFileName = "FreshPantry.store"

    /// App Group 容器内 store 的 URL;App Group 未授权(本地未签名 dev)时为 nil。
    static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupID)?
            .appending(path: storeFileName)
    }

    /// SwiftData 默认位置的旧 store(迁移源):`Application Support/default.store`。
    static func legacyDefaultStoreURL() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "default.store")
    }

    /// 一次性无损迁移:目标不存在、而旧 store 存在时,拷贝 `.store` / `-shm` /
    /// `-wal` 三件套到目标。目标已存在 → no-op(绝不覆盖)。拷贝失败容忍(调用方
    /// 回退旧位置打开,绝不丢数据)。纯文件操作,可注入 `fileManager` 单测。
    static func migrateStore(from legacy: URL, to target: URL, fileManager fm: FileManager = .default) {
        guard !fm.fileExists(atPath: target.path) else { return }
        guard fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: legacy.path + suffix)
            let dst = URL(fileURLWithPath: target.path + suffix)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    /// 生产容器。优先 App Group 容器(供小组件共享);若 App Group 不可用
    /// (本地未签名),回退 SwiftData 默认位置,保证 app 仍能启动。**仅主 app
    /// 调用**——它负责一次性迁移;小组件用 `makeSharedExisting()`,从不迁移。
    static func makeShared() throws -> ModelContainer {
        guard let storeURL = appGroupStoreURL() else {
            // 无 App Group 授权 → 默认位置(旧行为),小组件届时拿不到数据显示空态。
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        if let legacy = legacyDefaultStoreURL() {
            migrateStore(from: legacy, to: storeURL)
        }
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// 小组件用变体:**只在 App Group store 已存在时**打开它(从不迁移、从不新建)。
    /// 返回 nil → 小组件显示占位/空态,等用户首次启动 app 完成迁移。app 与 widget
    /// 跨进程并发读 + 单写由 SQLite WAL 兜底。
    static func makeSharedExisting() -> ModelContainer? {
        guard let storeURL = appGroupStoreURL(),
              FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try? ModelContainer(for: schema, configurations: [configuration])
    }
```

> `ModelConfiguration(schema:url:)` 是 iOS 17+ API:`init(_ name: String? = nil, schema: Schema? = nil, url: URL, ...)`。若编译器对参数顺序报错,用 `ModelConfiguration(schema: schema, url: storeURL)` 的具名形式(已如上)。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/ModelContainerMigrationTests 2>&1 | tail -30
```

Expected: 3 tests passed。

- [ ] **Step 5: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift \
  apps/ios/FreshPantryTests/Widgets/ModelContainerMigrationTests.swift && \
  git commit -m "feat(ios): SwiftData store 迁移到 App Group 容器 + widget 只读变体"
```

---

### Task 4: WidgetDataReader + 四类投影值类型

widget 从共享容器派生展示数据。所有派生为纯逻辑,用内存容器单测。

**Files:**
- Modify: `apps/ios/FreshPantry/Domain/Rules/FoodLogStatistics.swift`(加 `recentWindowDays`)
- Modify: `apps/ios/FreshPantry/Features/Waste/WasteInsightsStore.swift`(`recentWindowDays` 转发,DRY)
- Create: `apps/ios/FreshPantry/Widgets/Shared/WidgetSnapshots.swift`
- Create: `apps/ios/FreshPantry/Widgets/Shared/WidgetDataReader.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/WidgetDataReaderTests.swift`

- [ ] **Step 0: 把减废窗口常量下沉 Domain(reader 复用,避免依赖 Features/ 的 WasteInsightsStore)**

在 `apps/ios/FreshPantry/Domain/Rules/FoodLogStatistics.swift` 的 `enum FoodLogStatistics {` 内、`computeStats` 之前加:

```swift
    /// 减废统计的有界滞留窗口(天)。app 的 WasteInsightsStore 与小组件 reader
    /// 共用此单一真源(Flutter `foodLogRecentWindow = Duration(days: 90)`)。
    static let recentWindowDays = 90
```

在 `apps/ios/FreshPantry/Features/Waste/WasteInsightsStore.swift` 中,把 `static let recentWindowDays = 90` 改为转发(保持其文档注释不变,只改值):

```swift
    static let recentWindowDays = FoodLogStatistics.recentWindowDays
```

- [ ] **Step 1: 投影值类型**

Create `apps/ios/FreshPantry/Widgets/Shared/WidgetSnapshots.swift`:

```swift
import Foundation

/// 临期投影。`daysRemaining` 按 widget 渲染时刻重算(每天跨午夜刷新后变化)。
struct WidgetExpiringSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let name: String
        let daysRemaining: Int?  // nil = 无到期日
        let state: FreshnessState
    }
    let expiredCount: Int
    let urgentCount: Int
    let soonCount: Int
    let items: [Item]

    var needsAttentionCount: Int { expiredCount + urgentCount + soonCount }
    static let empty = WidgetExpiringSnapshot(expiredCount: 0, urgentCount: 0, soonCount: 0, items: [])
}

/// 今日膳食投影(只含今天的条目)。
struct WidgetMealPlanSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let title: String
        let done: Bool
        let mealType: String?
    }
    let items: [Item]
    static let empty = WidgetMealPlanSnapshot(items: [])
}

/// 购物投影。`items` 已「未勾选优先」并截断;每行带 id 供交互按钮回写。
struct WidgetShoppingSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let id: String
        let name: String
        let isChecked: Bool
    }
    let uncheckedCount: Int
    let items: [Item]
    static let empty = WidgetShoppingSnapshot(uncheckedCount: 0, items: [])
}

/// 减废投影(复用 Domain 的 FoodLogStatistics 口径)。
struct WidgetWasteSnapshot: Equatable, Sendable {
    let useUpPercent: Int
    let rescuedCount: Int
    let consumedCount: Int
    let wastedCount: Int
    let isEmpty: Bool
    static let empty = WidgetWasteSnapshot(useUpPercent: 0, rescuedCount: 0, consumedCount: 0, wastedCount: 0, isEmpty: true)
}

/// 四类内容的合集快照,一次读取填满(Provider 只读一次容器)。
struct WidgetSnapshotBundle: Equatable, Sendable {
    var expiring: WidgetExpiringSnapshot = .empty
    var mealPlan: WidgetMealPlanSnapshot = .empty
    var shopping: WidgetShoppingSnapshot = .empty
    var waste: WidgetWasteSnapshot = .empty
    static let empty = WidgetSnapshotBundle()
}
```

- [ ] **Step 2: 写失败的测试**

Create `apps/ios/FreshPantryTests/Widgets/WidgetDataReaderTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import FreshPantry

@MainActor
struct WidgetDataReaderTests {
    private let hh = "hh-test"
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } // 固定 now

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    @Test func expiringTiersSortedAndCounted() async throws {
        let container = try makeContainer()
        let inv = InventoryRepository(modelContainer: container)
        let cal = Calendar.current
        // expired(-1天), urgent(+1天), soon(freshness 低 + 无近到期), fresh(高 freshness)
        func ing(_ name: String, days: Int?, fresh: Double) -> Ingredient {
            Ingredient(
                id: UUID().uuidString, name: name, quantity: "1", unit: "份",
                imageUrl: "", freshnessPercent: fresh, state: .fresh,
                expiryDate: days.map { cal.date(byAdding: .day, value: $0, to: now())! }
            )
        }
        try await inv.saveItems(hh, [
            ing("过期菜", days: -1, fresh: 0.1),
            ing("紧急奶", days: 1, fresh: 0.4),
            ing("将过期", days: nil, fresh: 0.3),
            ing("新鲜肉", days: 10, fresh: 0.9),
        ])

        let reader = WidgetDataReader(container: container)
        let snap = await reader.expiringSnapshot(householdID: hh, now: now(), limit: 8)

        #expect(snap.expiredCount == 1)
        #expect(snap.urgentCount == 1)
        #expect(snap.soonCount == 1)
        #expect(snap.needsAttentionCount == 3)       // 新鲜肉不计
        #expect(snap.items.first?.name == "过期菜")    // expired 排最前
        #expect(snap.items.first?.daysRemaining == -1)
    }

    @Test func mealPlanShowsOnlyToday() async throws {
        let container = try makeContainer()
        let repo = MealPlanRepository(modelContainer: container)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        func entry(_ name: String, date: Date, done: Bool = false) -> MealPlanEntry {
            MealPlanEntry(id: UUID().uuidString, date: date, recipeId: "r", recipeName: name,
                          servings: 1, done: done, remoteVersion: 0)
        }
        try await repo.saveEntries(hh, [
            entry("番茄炒蛋", date: today),
            entry("红烧肉", date: today, done: true),
            entry("明天的菜", date: tomorrow),
        ])

        let reader = WidgetDataReader(container: container)
        let snap = await reader.mealPlanSnapshot(householdID: hh, now: now())

        #expect(snap.items.count == 2)
        #expect(snap.items.contains { $0.title == "番茄炒蛋" && !$0.done })
        #expect(snap.items.contains { $0.title == "红烧肉" && $0.done })
        #expect(!snap.items.contains { $0.title == "明天的菜" })
    }

    @Test func shoppingUncheckedFirstAndCounted() async throws {
        let container = try makeContainer()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.upsert(hh, ShoppingItem(id: "a", name: "牛奶", detail: "", category: FoodCategories.other, isChecked: true))
        try await repo.upsert(hh, ShoppingItem(id: "b", name: "鸡蛋", detail: "", category: FoodCategories.other, isChecked: false))

        let reader = WidgetDataReader(container: container)
        let snap = await reader.shoppingSnapshot(householdID: hh, limit: 8)

        #expect(snap.uncheckedCount == 1)
        #expect(snap.items.first?.name == "鸡蛋")     // 未勾选优先
        #expect(snap.items.first?.isChecked == false)
    }

    @Test func wasteUsesDomainStats() async throws {
        let container = try makeContainer()
        let repo = FoodLogRepository(modelContainer: container)
        func log(_ outcome: FoodLogOutcome, expiring: Bool = false) -> FoodLogEntry {
            FoodLogEntry(id: UUID().uuidString, name: "x", category: FoodCategories.other,
                         outcome: outcome, loggedAt: now(), wasExpiring: expiring, remoteVersion: 0)
        }
        try await repo.append(hh, log(.consumed, expiring: true))
        try await repo.append(hh, log(.consumed))
        try await repo.append(hh, log(.wasted))

        let reader = WidgetDataReader(container: container)
        let snap = await reader.wasteSnapshot(householdID: hh, now: now())

        #expect(snap.consumedCount == 2)
        #expect(snap.wastedCount == 1)
        #expect(snap.rescuedCount == 1)
        #expect(snap.useUpPercent == 67)
        #expect(!snap.isEmpty)
    }
}
```

> 若 `InventoryRepository.saveItems` / `FoodLogRepository.append` 的精确签名与上面不符,在 Step 2 编译失败信息里会暴露;按真实签名微调测试的写入方式(读 `Persistence/Repositories/InventoryRepository.swift`、`FoodLogRepository.swift` 顶部方法列表确认)。

- [ ] **Step 3: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetDataReaderTests 2>&1 | tail -30
```

Expected: 编译失败(`WidgetDataReader` 不存在)。

- [ ] **Step 4: 实现 WidgetDataReader**

Create `apps/ios/FreshPantry/Widgets/Shared/WidgetDataReader.swift`:

```swift
import Foundation
import SwiftData

/// 从共享 SwiftData 容器派生小组件展示数据。复用既有 `@ModelActor` repo 加载,
/// 派生口径对齐 app(`ExpiryCalculator` 临期分级 + `DashboardStore.isNonFresh`,
/// `FoodLogStatistics` 减废)。所有方法纯读不写。
struct WidgetDataReader {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// 一次读满四类内容(Provider 调用,只开一次容器)。
    func snapshotBundle(householdID: String, now: Date) async -> WidgetSnapshotBundle {
        async let expiring = expiringSnapshot(householdID: householdID, now: now, limit: 8)
        async let mealPlan = mealPlanSnapshot(householdID: householdID, now: now)
        async let shopping = shoppingSnapshot(householdID: householdID, limit: 8)
        async let waste = wasteSnapshot(householdID: householdID, now: now)
        return await WidgetSnapshotBundle(
            expiring: expiring, mealPlan: mealPlan, shopping: shopping, waste: waste
        )
    }

    // MARK: 临期

    func expiringSnapshot(householdID: String, now: Date, limit: Int) async -> WidgetExpiringSnapshot {
        let repo = InventoryRepository(modelContainer: container)
        guard let inventory = try? await repo.loadAllFor(householdID) else { return .empty }

        struct Tagged { let ingredient: Ingredient; let state: FreshnessState; let days: Int? }
        let tagged: [Tagged] = inventory.map { ing in
            let state = ExpiryCalculator.freshnessStateForExpiry(
                freshness: ing.freshnessPercent, expiryDate: ing.expiryDate, now: now
            )
            let days = ing.expiryDate.map { ExpiryCalculator.daysUntilExpiry($0, now: now) }
            return Tagged(ingredient: ing, state: state, days: days)
        }
        // 非新鲜 = 非 .fresh(等价 DashboardStore.isNonFresh,但 DashboardStore 在
        // Features/ 未共享进 widget,故就地判定——reader 是自包含的镜像派生)。
        let nonFresh = tagged.filter { $0.state != .fresh }

        // 排序:严重度(expired→urgent→soon),再最快到期优先(nil 到期日最后),稳定。
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ s: FreshnessState) -> Int { order.firstIndex(of: s) ?? order.count }
        let sorted = nonFresh.enumerated().sorted { lhs, rhs in
            let lr = rank(lhs.element.state), rr = rank(rhs.element.state)
            if lr != rr { return lr < rr }
            switch (lhs.element.days, rhs.element.days) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)

        func count(_ s: FreshnessState) -> Int { nonFresh.lazy.filter { $0.state == s }.count }
        let items = sorted.prefix(limit).map {
            WidgetExpiringSnapshot.Item(name: $0.ingredient.name, daysRemaining: $0.days, state: $0.state)
        }
        return WidgetExpiringSnapshot(
            expiredCount: count(.expired),
            urgentCount: count(.urgent),
            soonCount: count(.expiringSoon),
            items: Array(items)
        )
    }

    // MARK: 今日膳食

    func mealPlanSnapshot(householdID: String, now: Date) async -> WidgetMealPlanSnapshot {
        let repo = MealPlanRepository(modelContainer: container)
        guard let entries = try? await repo.loadAllFor(householdID) else { return .empty }
        let cal = Calendar.current
        let todays = entries.filter { cal.isDate($0.date, inSameDayAs: now) }
        let items = todays.map { entry -> WidgetMealPlanSnapshot.Item in
            let title = (entry.title?.isEmpty == false) ? entry.title! : entry.recipeName
            return WidgetMealPlanSnapshot.Item(title: title, done: entry.done, mealType: entry.mealType)
        }
        return WidgetMealPlanSnapshot(items: items)
    }

    // MARK: 购物

    func shoppingSnapshot(householdID: String, limit: Int) async -> WidgetShoppingSnapshot {
        let repo = ShoppingRepository(modelContainer: container)
        guard let all = try? await repo.loadAllFor(householdID) else { return .empty }
        let unchecked = all.lazy.filter { !$0.isChecked }.count
        // 未勾选优先,稳定保持源序。
        let sorted = all.enumerated().sorted { lhs, rhs in
            if lhs.element.isChecked != rhs.element.isChecked { return !lhs.element.isChecked }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let items = sorted.prefix(limit).map {
            WidgetShoppingSnapshot.Item(id: $0.id, name: $0.name, isChecked: $0.isChecked)
        }
        return WidgetShoppingSnapshot(uncheckedCount: unchecked, items: Array(items))
    }

    // MARK: 减废

    func wasteSnapshot(householdID: String, now: Date) async -> WidgetWasteSnapshot {
        let repo = FoodLogRepository(modelContainer: container)
        // 窗口常量在 Domain 的 FoodLogStatistics(WasteInsightsStore 在 Features/
        // 未共享进 widget;两者经 FoodLogStatistics.recentWindowDays 单一真源)。
        let sinceMs = Int(now.addingTimeInterval(-Double(FoodLogStatistics.recentWindowDays) * 86_400).timeIntervalSince1970 * 1000)
        guard let entries = try? await repo.loadRecentFor(householdID, sinceMs: sinceMs) else { return .empty }
        let stats = FoodLogStatistics.computeStats(entries)
        return WidgetWasteSnapshot(
            useUpPercent: stats.useUpPercent,
            rescuedCount: stats.rescued,
            consumedCount: stats.consumed,
            wastedCount: stats.wasted,
            isEmpty: stats.isEmpty
        )
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetDataReaderTests 2>&1 | tail -30
```

Expected: 4 tests passed。

- [ ] **Step 6: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Widgets/Shared/WidgetSnapshots.swift \
  apps/ios/FreshPantry/Widgets/Shared/WidgetDataReader.swift \
  apps/ios/FreshPantryTests/Widgets/WidgetDataReaderTests.swift && \
  git commit -m "feat(ios): WidgetDataReader 四类内容投影"
```

---

### Task 5: ShoppingToggleService(交互勾选 + 记 outbox)

widget 交互按钮的可测核心:翻转 store 中购物项 + 直接记一条 `.toggleChecked` outbox 操作(不经 SyncWriter,避开网络层)。

**Files:**
- Create: `apps/ios/FreshPantry/Widgets/Shared/ShoppingToggleService.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/ShoppingToggleServiceTests.swift`

- [ ] **Step 1: 写失败的测试**

Create `apps/ios/FreshPantryTests/Widgets/ShoppingToggleServiceTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import FreshPantry

@MainActor
struct ShoppingToggleServiceTests {
    private let hh = "hh-toggle"
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    @Test func togglesCheckedAndRecordsOutboxOp() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let shopping = ShoppingRepository(modelContainer: container)
        try await shopping.upsert(hh, ShoppingItem(id: "x1", name: "牛奶", detail: "", category: FoodCategories.other, isChecked: false, remoteVersion: 3))

        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: hh, itemID: "x1", clientID: "cli-1", now: now()
        )
        #expect(ok)

        // store 已翻转
        let after = try await shopping.loadAllFor(hh).first { $0.id == "x1" }
        #expect(after?.isChecked == true)

        // outbox 记了一条 .toggleChecked,baseVersion = 旧 remoteVersion(3)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let ops = try await outbox.loadPending()
        #expect(ops.count == 1)
        #expect(ops.first?.entityType == .shoppingItem)
        #expect(ops.first?.operation == .toggleChecked)
        #expect(ops.first?.entityId == "x1")
        #expect(ops.first?.baseVersion == 3)
        #expect(ops.first?.clientId == "cli-1")
        if case .bool(let v)? = ops.first?.patch["isChecked"] { #expect(v == true) } else { Issue.record("patch 缺 isChecked") }
    }

    @Test func localOnlySkipsOutbox() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let shopping = ShoppingRepository(modelContainer: container)
        try await shopping.upsert("", ShoppingItem(id: "y1", name: "蛋", detail: "", category: FoodCategories.other, isChecked: false))

        // householdID 空 = 仅本地:翻转持久化,但不记 outbox(无远程)。
        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: "", itemID: "y1", clientID: "cli-1", now: now()
        )
        #expect(ok)
        #expect((try await shopping.loadAllFor("").first { $0.id == "y1" })?.isChecked == true)
        #expect(try await SyncOutboxRepository(modelContainer: container).loadPending().isEmpty)
    }

    @Test func missingItemReturnsFalse() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: hh, itemID: "nope", clientID: "c", now: now()
        )
        #expect(!ok)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/ShoppingToggleServiceTests 2>&1 | tail -30
```

Expected: 编译失败(`ShoppingToggleService` 不存在)。

- [ ] **Step 3: 实现 ShoppingToggleService**

Create `apps/ios/FreshPantry/Widgets/Shared/ShoppingToggleService.swift`:

```swift
import Foundation
import SwiftData

/// 小组件交互勾选的可测核心。翻转共享 store 里某购物项的 `isChecked`,并在有
/// 家庭作用域时直接记一条 `.toggleChecked` outbox 操作(刻意不经 `SyncWriter`,
/// 那会把 `SyncCoordinator`→Supabase 网络层拖进 widget)。app 下次前台用既有
/// `SyncCoordinator` 推送这条 op。完整对齐 `ShoppingStore.toggleChecked` 的写口径。
enum ShoppingToggleService {
    /// 返回是否翻转成功(目标行不存在 / 写失败 → false)。
    @discardableResult
    static func toggle(container: ModelContainer, householdID: String, itemID: String, clientID: String, now: Date) async -> Bool {
        let shopping = ShoppingRepository(modelContainer: container)
        guard let all = try? await shopping.loadAllFor(householdID),
              let prior = all.first(where: { $0.id == itemID }) else { return false }

        let toggled = prior.copyWith(isChecked: !prior.isChecked)
        guard (try? await shopping.updateRow(householdID, toggled)) == true else { return false }

        // 仅本地(无家庭)→ 已持久化,无需 outbox(无远程可推)。
        guard !householdID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }

        let outbox = SyncOutboxRepository(modelContainer: container)
        let op = SyncOperation(
            id: UUID().uuidString.lowercased(),
            householdId: householdID,
            entityType: .shoppingItem,
            entityId: toggled.id,
            operation: .toggleChecked,
            patch: ["isChecked": .bool(toggled.isChecked)],
            baseVersion: prior.remoteVersion,
            clientId: clientID,
            createdAt: now
        )
        try? await outbox.enqueue(op)
        return true
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/ShoppingToggleServiceTests 2>&1 | tail -30
```

Expected: 3 tests passed。

- [ ] **Step 5: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Widgets/Shared/ShoppingToggleService.swift \
  apps/ios/FreshPantryTests/Widgets/ShoppingToggleServiceTests.swift && \
  git commit -m "feat(ios): ShoppingToggleService widget 勾选写路径"
```

---

### Task 6: WidgetDeepLinkRouter(app 端深链路由)

解析 `freshpantry://` host 到内容目标,RootView/DashboardView 消费驱动跳转。

**Files:**
- Create: `apps/ios/FreshPantry/Widgets/App/WidgetDeepLinkRouter.swift`
- Test: `apps/ios/FreshPantryTests/Widgets/WidgetDeepLinkRouterTests.swift`

- [ ] **Step 1: 写失败的测试**

Create `apps/ios/FreshPantryTests/Widgets/WidgetDeepLinkRouterTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

@MainActor
struct WidgetDeepLinkRouterTests {
    @Test func parsesKnownHosts() {
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://expiring")!) == .expiring)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://mealplan")!) == .mealPlan)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://shopping")!) == .shopping)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://waste")!) == .waste)
    }

    @Test func ignoresUnknownAndOtherSchemes() {
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://import-recipe?url=x")!) == nil)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "freshpantry://some-invite-token")!) == nil)
        #expect(WidgetDeepLinkRouter.destination(for: URL(string: "https://example.com/expiring")!) == nil)
    }

    @Test func captureSetsPendingForOwnedURLOnly() {
        let router = WidgetDeepLinkRouter()
        #expect(router.capture(url: URL(string: "freshpantry://shopping")!) == true)
        #expect(router.pending == .shopping)
        #expect(router.capture(url: URL(string: "freshpantry://import-recipe")!) == false)
        #expect(router.pending == .shopping) // 不被无关 URL 清掉
    }

    @Test func consumeClearsPending() {
        let router = WidgetDeepLinkRouter()
        _ = router.capture(url: URL(string: "freshpantry://waste")!)
        #expect(router.consume() == .waste)
        #expect(router.pending == nil)
        #expect(router.consume() == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetDeepLinkRouterTests 2>&1 | tail -30
```

Expected: 编译失败(`WidgetDeepLinkRouter` 不存在)。

- [ ] **Step 3: 实现 WidgetDeepLinkRouter**

Create `apps/ios/FreshPantry/Widgets/App/WidgetDeepLinkRouter.swift`:

```swift
import Foundation

/// 小组件深链路由(app 端)。`freshpantry://<host>` → 内容目标。临期/今日膳食/
/// 减废三屏由首页 `DashboardRoute` push;购物切到购物 tab。与 invite / recipe
/// import 的 capture 互斥:只认下面四个固定 host,其余 URL `capture` 返回 false,
/// 让 `onOpenURL` 继续交给其他 router。
@Observable
@MainActor
final class WidgetDeepLinkRouter {
    enum Destination: Hashable, Sendable {
        case expiring, mealPlan, shopping, waste
    }

    private(set) var pending: Destination?

    /// 纯解析:已知 host → 目标,否则 nil。不认 scheme 以外或带 query 的(如
    /// import-recipe)。
    static func destination(for url: URL) -> Destination? {
        guard url.scheme == "freshpantry" else { return nil }
        switch url.host() {
        case "expiring": return .expiring
        case "mealplan": return .mealPlan
        case "shopping": return .shopping
        case "waste": return .waste
        default: return nil
        }
    }

    /// 拦截本 router 拥有的 URL;命中则记 pending 返回 true,否则不动返回 false。
    @discardableResult
    func capture(url: URL) -> Bool {
        guard let dest = Self.destination(for: url) else { return false }
        pending = dest
        return true
    }

    @discardableResult
    func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }

    func clear() { pending = nil }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests/WidgetDeepLinkRouterTests 2>&1 | tail -30
```

Expected: 4 tests passed。

- [ ] **Step 5: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Widgets/App/WidgetDeepLinkRouter.swift \
  apps/ios/FreshPantryTests/Widgets/WidgetDeepLinkRouterTests.swift && \
  git commit -m "feat(ios): WidgetDeepLinkRouter 深链路由解析"
```

---

### Task 7: WidgetRefreshCoordinator(app 端 reload seam)

集中 `reloadAllTimelines()` 调用点,便于将来收敛/测试。

**Files:**
- Create: `apps/ios/FreshPantry/Widgets/App/WidgetRefreshCoordinator.swift`

- [ ] **Step 1: 实现(无单测——薄封装系统 API)**

Create `apps/ios/FreshPantry/Widgets/App/WidgetRefreshCoordinator.swift`:

```swift
import Foundation
import WidgetKit

/// 单一刷新 seam:app 在数据可能变化时让所有时间线重载。集中在此,既便于
/// 将来扩展(按 kind 精细刷新),也避免散落的 WidgetKit 调用。
enum WidgetRefreshCoordinator {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 2: 构建确认编译**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`(`Widgets/App/` 目录此前未被任一 target 引用;app target 的 `FreshPantry` 源路径已包含整个 `FreshPantry/` 目录,故自动纳入)。

- [ ] **Step 3: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/Widgets/App/WidgetRefreshCoordinator.swift && \
  git commit -m "feat(ios): WidgetRefreshCoordinator 刷新 seam"
```

---

### Task 8: Widget 配置 intent + AppEnum + 时间线 Provider

**Files:**
- Create: `apps/ios/FreshPantryWidgets/WidgetContentChoice.swift`
- Create: `apps/ios/FreshPantryWidgets/WidgetProvider.swift`

> 实现前用 find-docs 核对当前 `AppIntents` / `WidgetKit` 的 `AppIntentConfiguration` / `AppIntentTimelineProvider` / `AppEnum` API(iOS 26),以下代码按 iOS 17+ 稳定 API 写就。

- [ ] **Step 1: 内容选择枚举 + 配置 intent**

Create `apps/ios/FreshPantryWidgets/WidgetContentChoice.swift`:

```swift
import AppIntents
import WidgetKit

/// 用户在长按编辑 widget 时可选的内容。
enum WidgetContentChoice: String, AppEnum {
    case expiring, mealPlan, shopping, waste

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "组件内容" }
    static var caseDisplayRepresentations: [WidgetContentChoice: DisplayRepresentation] {
        [
            .expiring: "临期食材",
            .mealPlan: "今日膳食",
            .shopping: "购物清单",
            .waste: "减废成效",
        ]
    }
}

/// widget 配置 intent:选择展示哪类内容(默认临期)。
struct SelectWidgetContentIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "选择内容" }
    static var description: IntentDescription { "选择小组件展示的内容" }

    @Parameter(title: "内容", default: .expiring)
    var content: WidgetContentChoice
}
```

- [ ] **Step 2: 时间线 Provider + Entry**

Create `apps/ios/FreshPantryWidgets/WidgetProvider.swift`:

```swift
import SwiftData
import WidgetKit

/// 一条时间线条目:渲染时刻 + 选中内容 + 四类快照合集。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetContentChoice
    let bundle: WidgetSnapshotBundle
    /// App Group store 尚不存在(用户未首启完成迁移)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

struct WidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: .expiring, bundle: .empty, needsAppLaunch: false)
    }

    func snapshot(for configuration: SelectWidgetContentIntent, in context: Context) async -> WidgetEntry {
        await entry(for: configuration.content, now: .now)
    }

    func timeline(for configuration: SelectWidgetContentIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date.now
        let current = await entry(for: configuration.content, now: now)
        // 下次刷新:跨午夜(临期剩余天数每天重算)。app 在数据变更时另会显式 reload。
        let nextMidnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(6 * 3600)
        return Timeline(entries: [current], policy: .after(nextMidnight))
    }

    /// 读共享容器 + 当前家庭作用域,派生四类快照。容器不存在 → needsAppLaunch。
    private func entry(for content: WidgetContentChoice, now: Date) async -> WidgetEntry {
        guard let container = ModelContainerFactory.makeSharedExisting() else {
            return WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)
        }
        let householdID = WidgetSharedDefaults.readHouseholdID()
        let reader = WidgetDataReader(container: container)
        let bundle = await reader.snapshotBundle(householdID: householdID, now: now)
        return WidgetEntry(date: now, content: content, bundle: bundle, needsAppLaunch: false)
    }
}
```

- [ ] **Step 3: 构建确认编译**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantryWidgets/WidgetContentChoice.swift \
  apps/ios/FreshPantryWidgets/WidgetProvider.swift && \
  git commit -m "feat(ios): widget 配置 intent + 时间线 Provider"
```

---

### Task 9: Widget 视图(system + 锁屏配件)+ 装配 widget kind

**Files:**
- Create: `apps/ios/FreshPantryWidgets/WidgetContentViews.swift`
- Create: `apps/ios/FreshPantryWidgets/WidgetAccessoryViews.swift`
- Create: `apps/ios/FreshPantryWidgets/WidgetRootView.swift`
- Create: `apps/ios/FreshPantryWidgets/FreshPantryWidget.swift`
- Modify: `apps/ios/FreshPantryWidgets/FreshPantryWidgetBundle.swift`(去掉占位,挂真实 widget)

- [ ] **Step 1: system family 内容视图**

Create `apps/ios/FreshPantryWidgets/WidgetContentViews.swift`:

```swift
import SwiftUI
import WidgetKit

// MARK: 临期

struct ExpiringWidgetView: View {
    let snapshot: WidgetExpiringSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("临期 \(snapshot.needsAttentionCount) 件").font(.headline)
            }
            if snapshot.expiredCount > 0 {
                Text("已过期 \(snapshot.expiredCount)").font(.caption).foregroundStyle(.red)
            }
            if family != .systemSmall {
                ForEach(Array(snapshot.items.prefix(rowLimit).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(daysLabel(item.daysRemaining)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if snapshot.needsAttentionCount == 0 {
                Text("都很新鲜 🎉").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://expiring"))
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
    private func daysLabel(_ days: Int?) -> String {
        guard let days else { return "无到期" }
        if days < 0 { return "已过期" }
        if days == 0 { return "今天到期" }
        return "还剩 \(days) 天"
    }
}

// MARK: 今日膳食

struct MealPlanWidgetView: View {
    let snapshot: WidgetMealPlanSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife").foregroundStyle(.green)
                Text("今日膳食").font(.headline)
            }
            if snapshot.items.isEmpty {
                Text("今天还没排菜").font(.caption).foregroundStyle(.secondary)
            } else if family == .systemSmall {
                Text("\(snapshot.items.count) 顿待做").font(.subheadline)
            } else {
                ForEach(Array(snapshot.items.prefix(rowLimit).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Text(item.title).font(.subheadline).strikethrough(item.done).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://mealplan"))
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
}

// MARK: 购物(交互按钮在 Task 10 加入)

struct ShoppingWidgetView: View {
    let snapshot: WidgetShoppingSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "cart.fill").foregroundStyle(.blue)
                Text("购物 \(snapshot.uncheckedCount) 项待买").font(.headline)
            }
            if family == .systemSmall {
                if let first = snapshot.items.first { Text(first.name).font(.subheadline).lineLimit(1) }
            } else {
                ForEach(Array(snapshot.items.prefix(rowLimit).enumerated()), id: \.offset) { _, item in
                    ShoppingRowView(item: item)
                }
            }
            if snapshot.items.isEmpty {
                Text("清单是空的").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://shopping"))
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
}

/// 单行购物项。Task 10 会把前面的图标换成 `Button(intent:)` 交互勾选。
struct ShoppingRowView: View {
    let item: WidgetShoppingSnapshot.Item
    var body: some View {
        HStack {
            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isChecked ? .blue : .secondary)
            Text(item.name).font(.subheadline).strikethrough(item.isChecked).lineLimit(1)
        }
    }
}

// MARK: 减废

struct WasteWidgetView: View {
    let snapshot: WidgetWasteSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                Text("减废成效").font(.headline)
            }
            if snapshot.isEmpty {
                Text("还没有记录").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(snapshot.useUpPercent)%").font(.system(size: family == .systemSmall ? 34 : 28, weight: .bold))
                Text("用掉率").font(.caption).foregroundStyle(.secondary)
                if family != .systemSmall {
                    Text("抢救临期 \(snapshot.rescuedCount) 件 · 浪费 \(snapshot.wastedCount) 件")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://waste"))
    }
}
```

- [ ] **Step 2: 锁屏配件视图**

Create `apps/ios/FreshPantryWidgets/WidgetAccessoryViews.swift`:

```swift
import SwiftUI
import WidgetKit

/// accessoryCircular:临期件数环。
struct AccessoryCircularView: View {
    let snapshot: WidgetExpiringSnapshot
    var body: some View {
        Gauge(value: Double(min(snapshot.needsAttentionCount, 9)), in: 0...9) {
            Image(systemName: "exclamationmark.triangle")
        } currentValueLabel: {
            Text("\(snapshot.needsAttentionCount)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(URL(string: "freshpantry://expiring"))
    }
}

/// accessoryRectangular:可配置内容的一行摘要。
struct AccessoryRectangularView: View {
    let entry: WidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.content {
            case .expiring:
                Label("临期 \(entry.bundle.expiring.needsAttentionCount) 件", systemImage: "exclamationmark.triangle")
                if let first = entry.bundle.expiring.items.first {
                    Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .mealPlan:
                Label("今日 \(entry.bundle.mealPlan.items.count) 顿", systemImage: "fork.knife")
                if let first = entry.bundle.mealPlan.items.first {
                    Text(first.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .shopping:
                Label("待买 \(entry.bundle.shopping.uncheckedCount) 项", systemImage: "cart")
            case .waste:
                Label("用掉率 \(entry.bundle.waste.useUpPercent)%", systemImage: "leaf")
            }
        }
        .widgetURL(URL(string: contentDeepLink(entry.content)))
    }
}

/// accessoryInline:临期一句话。
struct AccessoryInlineView: View {
    let snapshot: WidgetExpiringSnapshot
    var body: some View {
        Text("临期 \(snapshot.needsAttentionCount) 件")
            .widgetURL(URL(string: "freshpantry://expiring"))
    }
}

func contentDeepLink(_ content: WidgetContentChoice) -> String {
    switch content {
    case .expiring: return "freshpantry://expiring"
    case .mealPlan: return "freshpantry://mealplan"
    case .shopping: return "freshpantry://shopping"
    case .waste: return "freshpantry://waste"
    }
}
```

- [ ] **Step 3: 按 family × content 分支的根视图**

Create `apps/ios/FreshPantryWidgets/WidgetRootView.swift`:

```swift
import SwiftUI
import WidgetKit

struct WidgetRootView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.needsAppLaunch {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("打开 Fresh Pantry").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(snapshot: entry.bundle.expiring)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(snapshot: entry.bundle.expiring)
        default:
            switch entry.content {
            case .expiring: ExpiringWidgetView(snapshot: entry.bundle.expiring, family: family)
            case .mealPlan: MealPlanWidgetView(snapshot: entry.bundle.mealPlan, family: family)
            case .shopping: ShoppingWidgetView(snapshot: entry.bundle.shopping, family: family)
            case .waste: WasteWidgetView(snapshot: entry.bundle.waste, family: family)
            }
        }
    }
}
```

- [ ] **Step 4: widget kind 定义**

Create `apps/ios/FreshPantryWidgets/FreshPantryWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct FreshPantryWidget: Widget {
    static let kind = "FreshPantryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectWidgetContentIntent.self,
            provider: WidgetProvider()
        ) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fresh Pantry")
        .description("临期 / 今日膳食 / 购物 / 减废,一眼掌握")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
```

- [ ] **Step 5: 用真实 widget 替换占位 bundle**

把 `apps/ios/FreshPantryWidgets/FreshPantryWidgetBundle.swift` 全文替换为:

```swift
import SwiftUI
import WidgetKit

@main
struct FreshPantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        FreshPantryWidget()
    }
}
```

- [ ] **Step 6: 构建确认编译**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantryWidgets && \
  git commit -m "feat(ios): widget 视图(system + 锁屏配件)+ 装配 widget kind"
```

---

### Task 10: 交互勾选(ToggleShoppingItemIntent + 购物行按钮)

**Files:**
- Create: `apps/ios/FreshPantryWidgets/ToggleShoppingItemIntent.swift`
- Modify: `apps/ios/FreshPantryWidgets/WidgetContentViews.swift`(`ShoppingRowView` 改用 `Button(intent:)`)

- [ ] **Step 1: 交互 intent**

Create `apps/ios/FreshPantryWidgets/ToggleShoppingItemIntent.swift`:

```swift
import AppIntents
import WidgetKit

/// widget 内勾选购物项。运行在 widget 进程:翻转共享 store + 记 outbox(经
/// `ShoppingToggleService`),再重载时间线让勾选即时反映。
struct ToggleShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        guard let container = ModelContainerFactory.makeSharedExisting() else { return .result() }
        let householdID = WidgetSharedDefaults.readHouseholdID()
        let clientID = WidgetSharedDefaults.readClientID()
        await ShoppingToggleService.toggle(
            container: container, householdID: householdID, itemID: itemID, clientID: clientID, now: .now
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- [ ] **Step 2: 购物行改交互按钮**

把 `apps/ios/FreshPantryWidgets/WidgetContentViews.swift` 里的 `ShoppingRowView` 整体替换为:

```swift
/// 单行购物项,带交互勾选按钮(iOS 17+)。点击翻转 store + 重载时间线。
struct ShoppingRowView: View {
    let item: WidgetShoppingSnapshot.Item
    var body: some View {
        HStack {
            Button(intent: ToggleShoppingItemIntent(itemID: item.id)) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            Text(item.name).font(.subheadline).strikethrough(item.isChecked).lineLimit(1)
            Spacer()
        }
    }
}
```

- [ ] **Step 3: 构建确认编译**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantryWidgets && \
  git commit -m "feat(ios): widget 购物清单交互勾选(ToggleShoppingItemIntent)"
```

---

### Task 11: App 集成(写 defaults / reload 触发 / 深链 capture / 路由消费)

把 app 侧的写入、刷新、深链路由全部接通。

**Files:**
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`
- Modify: `apps/ios/FreshPantry/App/FreshPantryApp.swift`
- Modify: `apps/ios/FreshPantry/App/RootView.swift`
- Modify: `apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift`

- [ ] **Step 1: AppDependencies 暴露 widgetDeepLinkRouter**

在 `apps/ios/FreshPantry/App/AppDependencies.swift` 中,仿照 `notificationTapRouter` 的声明,新增一个属性。找到现有 router 声明(如 `let notificationTapRouter: NotificationTapRouter`)并在其附近加:

```swift
    let widgetDeepLinkRouter = WidgetDeepLinkRouter()
```

(`WidgetDeepLinkRouter` 的 init 无参,直接赋初值即可——与其他 router 一致。)

- [ ] **Step 2: FreshPantryApp 注入环境 + 写 defaults + 深链 capture + reload**

在 `apps/ios/FreshPantry/App/FreshPantryApp.swift`:

(a) 顶部 import 加 `WidgetKit`(若 reload 调用需要;实际通过 `WidgetRefreshCoordinator` 封装,可不直接 import):无需改 import(用 `WidgetRefreshCoordinator`)。

(b) 在 `WindowGroup { RootView() ... }` 的环境注入链里(`.environment(dependencies.spotlightRouter)` 之后)加:

```swift
                .environment(dependencies.widgetDeepLinkRouter)
```

(c) 把 `.onOpenURL` 闭包改为(在 recipeImport 之后、invite 之前插入 widget capture):

```swift
                .onOpenURL { url in
                    if dependencies.recipeImportRouter.capture(url: url) { return }
                    if dependencies.widgetDeepLinkRouter.capture(url: url) { return }
                    if dependencies.inviteRouter.capture(url: url) { return }
                    dependencies.clientProvider.handleOpenURL(url)
                }
```

(d) 在现有 `.task { Self.scheduleAppRefresh() }` 之后,新增「写 App Group 身份 + 首刷」与「家庭切换时更新」:

```swift
                // WIDGET 身份镜像:把当前家庭 + clientId 写进 App Group,供小组件
                // 读取查询作用域 / 构造 outbox 操作;并触发一次时间线重载。
                .task {
                    WidgetSharedDefaults.writeIdentity(
                        householdID: dependencies.householdID,
                        clientID: dependencies.syncSession.clientId
                    )
                    WidgetRefreshCoordinator.reloadAll()
                }
                .onChange(of: dependencies.householdID) { _, newID in
                    WidgetSharedDefaults.writeIdentity(
                        householdID: newID,
                        clientID: dependencies.syncSession.clientId
                    )
                    WidgetRefreshCoordinator.reloadAll()
                }
```

(e) 在已有的 `.onChange(of: scenePhase)` 闭包的 `if phase == .background { ... }` 分支内,首行加一次 reload(进后台前刷新,用户回桌面即见最新):

```swift
                    if phase == .background {
                        WidgetRefreshCoordinator.reloadAll()
                        Self.scheduleAppRefresh()
                        // ... 既有 notificationCoordinator.reschedule ...
```

- [ ] **Step 3: RootView 消费 widgetDeepLinkRouter + dataRevision reload**

在 `apps/ios/FreshPantry/App/RootView.swift`:

(a) 环境声明区(`@Environment(SpotlightRouter.self) private var spotlightRouter` 附近)加:

```swift
    @Environment(WidgetDeepLinkRouter.self) private var widgetDeepLinkRouter
```

(b) 在 `tabs` 的修饰符链里(与其他 `.task(id:)` / `.onChange` 并列,例如挨着 `spotlightRouter` 的 `.task(id:)`)加一个消费器。**只负责切 tab**;首页内三屏的 push 交给 DashboardView(见 Step 4),故这里对 dashboard 类目标只切到 `.home`、不 consume:

```swift
        // 小组件深链:购物切购物 tab(就地 consume);临期/今日膳食/减废切到
        // 首页 tab,由 DashboardView 消费并 push 对应 DashboardRoute。
        .task(id: widgetDeepLinkRouter.pending) {
            guard let dest = widgetDeepLinkRouter.pending else { return }
            switch dest {
            case .shopping:
                widgetDeepLinkRouter.consume()
                selection = .shopping
            case .expiring, .mealPlan, .waste:
                selection = .home
            }
        }
```

(c) 在已有的 `.onChange(of: dependencies.syncSession.dataRevision) { Task { await refreshPendingCount() } }` 闭包体里追加一行 reload(远程合并后刷新 widget):

```swift
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await refreshPendingCount() }
            WidgetRefreshCoordinator.reloadAll()
        }
```

- [ ] **Step 4: DashboardView 消费 widgetDeepLinkRouter → push DashboardRoute**

在 `apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift`:

(a) 环境声明加(挨着 `@Environment(NotificationTapRouter.self) private var tapRouter`):

```swift
    @Environment(WidgetDeepLinkRouter.self) private var widgetDeepLinkRouter
```

(b) 在已有的 `.task(id: tapRouter.pendingTap) { ... }`(push 临期)旁边,新增 widget 深链消费器:

```swift
        // 小组件深链(临期/今日膳食/减废)→ push 对应 DashboardRoute。购物由
        // RootView 切 tab 处理(此处返回 nil 不消费)。
        .task(id: widgetDeepLinkRouter.pending) {
            guard let dest = widgetDeepLinkRouter.pending else { return }
            let route: DashboardRoute?
            switch dest {
            case .expiring: route = .expiring
            case .mealPlan: route = .mealPlan
            case .waste: route = .wasteInsights
            case .shopping: route = nil
            }
            guard let route else { return }
            widgetDeepLinkRouter.consume()
            if path.last != route { path.append(route) }
        }
```

- [ ] **Step 5: 构建 + 全量单测**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodegen generate && \
  xcodebuild build -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -20 && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **` + 全部单测通过(含新增 6 个套件 + 既有回归)。

- [ ] **Step 6: Commit**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry && \
  git add apps/ios/FreshPantry/App apps/ios/FreshPantry/Features/Dashboard/DashboardView.swift && \
  git commit -m "feat(ios): app 集成 widget(写 App Group 身份/刷新触发/深链路由)"
```

---

### Task 12: 端到端验证(模拟器实跑 widget)

代码全绿不等于 widget 真的工作。手动在模拟器装 widget、验证四类内容、交互勾选、深链跳转、迁移。

- [ ] **Step 1: 跑全量测试套件(最终回归)**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -40
```

Expected: 全部 `FreshPantryTests` 通过(UI 测试如偶发 flaky,按 memory 里 `rerun --failed` 经验重跑)。

- [ ] **Step 2: 装 app + widget 到模拟器,人工验证清单**

在 Xcode 选 `FreshPantry` scheme + iPhone 16 Pro 模拟器 Run(让 app 首启完成 store 迁移并写 App Group 身份)。然后长按主屏空白 → 加 Fresh Pantry 小组件。逐项确认:

- [ ] 中号 widget 默认显示「临期」内容,数字与 app 首页临期一致。
- [ ] 长按 widget → 编辑 → 切换内容为「今日膳食 / 购物清单 / 减废成效」,各自渲染正确。
- [ ] 小号 / 大号 / 锁屏配件(circular/rectangular/inline)各 family 不崩、布局合理。
- [ ] 购物清单 widget 点击某行勾选按钮 → 该行立即变勾选态(说明交互写 + reload 生效);切回 app 购物 tab 确认该项已勾选(共享 store 单一数据源)。
- [ ] 点击 widget(非按钮区)→ app 打开并跳到对应位置(临期屏 / 首页膳食 push / 购物 tab / 减废屏)。
- [ ] (迁移)若有旧版本数据:升级安装后 app 首启数据不丢(`makeShared` 迁移路径)。新装则 widget 在 app 首启前显示「打开 Fresh Pantry」占位,首启后正常。

- [ ] **Step 3: 记录验证结果**

把 Step 2 的逐项结果如实写进收尾说明(哪些通过、哪些待真机)。**交互按钮 + 锁屏配件建议真机复核**(模拟器对 AppIntent 交互 + 锁屏渲染偶有差异)。

> 本任务无 commit(纯验证);若验证暴露 bug,回到对应 Task 修复 + 重测。

---

### Task 13: Release 签名 + CI(Apple 开发者后台手动步骤,发版前 gating)

Debug 自动签名本地可跑;**Release/TestFlight 需手动准备描述文件**(对齐 memory「TestFlight deploy」里主 app/ShareExtension 的 manual distribution 模式)。此任务多为后台操作,不产代码。

- [ ] **Step 1: App ID 加 App Groups 能力**

Apple Developer 后台 → Identifiers:
- 主 App ID `com.kunish.freshPantry`:启用 App Groups,关联 `group.com.kunish.freshPantry`(不存在则先在 App Groups 里新建该 group)。
- 新建 Widget 的 App ID `com.kunish.freshPantry.Widgets`:同样启用 App Groups 关联同一 group。

- [ ] **Step 2: 重新生成 / 新建描述文件**

- 重新生成 `FreshPantry App Store`(现含 App Group 能力)。
- 新建 `FreshPantry Widgets App Store`(App Store 分发,bundle `com.kunish.freshPantry.Widgets`,含 App Group)——名称须与 project.yml Task 1 Step 6 里的 `PROVISIONING_PROFILE_SPECIFIER` 一致。

- [ ] **Step 3: CI 导入新 profile**

在 TestFlight/CI 部署流程里加入新 widget 描述文件的导入(与现有 app/ShareExtension profile 导入同处)。参考 memory「TestFlight deploy」的 manual distribution 流程。

- [ ] **Step 4: Release 归档冒烟**

本地用 Release 配置 archive 一次,确认主 app + ShareExtension + Widgets 三个 bundle 都用对应 manual profile 签过、归档成功:

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry/apps/ios && \
  xcodebuild archive -scheme FreshPantry -configuration Release \
  -archivePath /tmp/FreshPantry.xcarchive \
  -destination 'generic/platform=iOS' 2>&1 | tail -30
```

Expected: `** ARCHIVE SUCCEEDED **`,且 archive 内含 `PlugIns/FreshPantryWidgets.appex`。

> 此步依赖证书/profile 到位;若本地无分发证书,标记为发版机执行。

---

## YAGNI(本期不做)

- 不做 widget 内「加购 / 扫码」等额外交互(v1 仅购物勾选)。
- 不拆多个独立 widget kind(单可配置 widget)。
- 不引入 widget 专属网络拉取(纯走共享 store,离线优先)。
- 不重构持久化层为独立 framework(XcodeGen 同源 target 成员关系即可)。
- 不做逐条本地 mutation 的 widget 刷新(后台 / 远程合并 / 身份写入刷新已够)。
