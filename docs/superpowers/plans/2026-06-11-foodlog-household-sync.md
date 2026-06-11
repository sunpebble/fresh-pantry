# FoodLog 家庭同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 FoodLog(食物去向/减废记录)成为最后一个参与家庭共享同步的实体,补齐家庭共享完整性,统计口径由「本设备」变「全家」。

**Architecture:** 逐处照搬 `MealPlanEntry` 的 payload-blob 同步链路(codec/merge/gateway/coordinator/remote-repo),append-only 让合并退化成「远端全量 ∪ 本地未同步行」。id 从 `fl_<ms>` 切到 UUID,历史记录在进家庭同步前由一次性幂等迁移重写 id 后完整回填上云。

**Tech Stack:** SwiftUI + SwiftData(`@ModelActor`)+ Supabase(Swift SDK,payload-blob jsonb 表 + RLS + realtime)+ Swift Testing(`@Test`/`#expect`)。

**Spec:** `docs/superpowers/specs/2026-06-11-foodlog-household-sync-design.md`

**验证命令(每个含 Swift 改动的 task 末尾跑):**
```bash
cd apps/ios && xcodebuild test \
  -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests 2>&1 | tail -20
```
> 新增 `.swift` 文件后先 `cd apps/ios && xcodegen generate`。本 plan 不新增文件(全部改既有文件)+ 1 个 `.sql`,故无需 xcodegen,除非 Task 选择把迁移拆成新文件。

---

## File Structure(改动落点)

| 文件 | 责任 | Task |
|---|---|---|
| `Domain/Models/FoodLogEntry.swift` | id 格式 `fl_<ms>`→UUID | 1 |
| `FreshPantryTests/DateEncodingParityTests.swift` | 适配 newId 断言 | 1 |
| `Persistence/Repositories/FoodLogRepository.swift` | 加 `migrateLegacyIds()` | 2 |
| `FreshPantryTests/RepositoryTests.swift` | 迁移测试 | 2 |
| `Domain/Enums.swift` | `SyncEntityType` 加 `.foodLogEntry` | 3 |
| `Sync/RemoteRowCodec.swift` | `foodLogEntryRowFromJson/ForUpsert` | 3 |
| `Sync/SupabaseSyncGateway.swift` | `EntityCodec.foodLog` + pushOperation 分支 | 3 |
| `FreshPantryTests/Sync/FoodLogSyncCodecTests.swift`(新) | codec round-trip | 3 |
| `Sync/HouseholdMergePolicy.swift` | `mergeFoodLog` + `isLocalOnlyFoodLog` | 4 |
| `FreshPantryTests/Sync/FoodLogMergeTests.swift`(新) | 并集语义 | 4 |
| `Sync/RemotePantryRepository.swift` | Table + load/upsert/watch | 5 |
| `Sync/HouseholdContentSyncCoordinator.swift` | 注入 + startSync + uploadLocalOnly + subscribe + applyFoodLogRows + 迁移调用 | 6 |
| `App/AppDependencies.swift` | 注入 foodLogRepository 到 coordinator | 6 |
| `Features/Recipes/DeductionController.swift` | consumed departures enqueue create | 7 |
| `Features/Inventory/InventoryStore.swift` | remove→create、undoRemove→delete | 7 |
| `FreshPantryTests/DeductionFlowTests.swift` / `InventoryStoreTests.swift` | enqueue 断言 | 7 |
| `supabase/migrations/20260611120000_food_log_entries_sync.sql`(新) | 建表 + RLS + trigger + realtime | 8 |

---

## Task 1: FoodLogEntry id → UUID

**Files:**
- Modify: `apps/ios/FreshPantry/Domain/Models/FoodLogEntry.swift:57-58`
- Test: `apps/ios/FreshPantryTests/DateEncodingParityTests.swift:102`

- [ ] **Step 1: 改失败测试** — `DateEncodingParityTests.swift:102`,把 `fl_` 前缀断言换成 UUID 校验:

```swift
// 旧: #expect(FoodLogEntry.newId().hasPrefix("fl_"))
let id = FoodLogEntry.newId()
#expect(UUID(uuidString: id) != nil)              // 合法 UUID
#expect(id == id.lowercased())                    // 小写(gateway 的 isUuid 期望)
```

- [ ] **Step 2: 跑测试确认 red**

Run 上方验证命令(可加 `-only-testing:FreshPantryTests/DateEncodingParityTests`)。
Expected: FAIL(`newId()` 仍返回 `fl_…`,`UUID(uuidString:)` 为 nil)。

- [ ] **Step 3: 改 `newId()`** — `FoodLogEntry.swift:57-58`:

```swift
/// Canonical id format: lowercase UUID (synced to a Supabase `uuid` PK column).
static func newId() -> String { UUID().uuidString.lowercased() }
```

- [ ] **Step 4: 跑测试确认 green**

Expected: PASS。同时确认 `DateEncodingParityTests:63/71`、`InventoryStoreTests:345`、`RepositoryTests:144` 仍绿——它们用**显式** `id: "fl_1"` 构造,不经 `newId()`,不受影响。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Domain/Models/FoodLogEntry.swift apps/ios/FreshPantryTests/DateEncodingParityTests.swift
git commit -m "feat(ios): FoodLogEntry id 切换为 UUID(家庭同步前置)"
```

---

## Task 2: FoodLogRepository 一次性 id 迁移

把本地遗留 `fl_` 前缀记录重写为 UUID(同时改自然键 id 与 payload 内 id)。幂等:迁移后无 `fl_` 前缀,重跑即 no-op。append-only 纯分析数据无外键引用,重写安全。

**Files:**
- Modify: `apps/ios/FreshPantry/Persistence/Repositories/FoodLogRepository.swift`(在 `saveEntries` 后加方法)
- Test: `apps/ios/FreshPantryTests/RepositoryTests.swift`

- [ ] **Step 1: 写失败测试** — `RepositoryTests.swift` 加(放在 FoodLog 相关测试附近):

```swift
@Test func migrateLegacyFoodLogIdsRewritesPrefixedRowsAndIsIdempotent() async throws {
    let container = try ModelContainerFactory.makeInMemory()
    let repo = FoodLogRepository(modelContainer: container)
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    try await repo.append("home", FoodLogEntry(id: "fl_1", name: "牛奶", outcome: .consumed, loggedAt: t))
    let keep = FoodLogEntry(id: "11111111-1111-4111-8111-111111111111", name: "番茄", outcome: .wasted, loggedAt: t)
    try await repo.append("home", keep)

    let changed = try await repo.migrateLegacyIds()
    #expect(changed == 1)                                  // 只动 fl_ 那条

    let loaded = try await repo.loadAllFor("home")
    let ids = Set(loaded.map(\.id))
    #expect(!ids.contains("fl_1"))                         // 旧 id 不在了
    #expect(ids.contains(keep.id))                         // UUID 行原样保留
    let migrated = try #require(loaded.first { $0.name == "牛奶" })
    #expect(UUID(uuidString: migrated.id) != nil)          // 新 id 是 UUID
    #expect(migrated.outcome == .consumed)                 // 其余字段无损
    #expect(migrated.loggedAt == t)

    let again = try await repo.migrateLegacyIds()
    #expect(again == 0)                                    // 幂等
}
```

- [ ] **Step 2: 跑测试确认 red** — Expected: FAIL(`migrateLegacyIds` 未定义)。

- [ ] **Step 3: 实现** — `FoodLogRepository.swift`,在 `saveEntries` 方法后、`decode` 前插入:

```swift
/// One-shot, idempotent: rewrites legacy `fl_<ms>` ids to lowercase UUIDs so
/// the row can land in the Supabase `uuid` PK column. Re-encodes the payload's
/// own `id` too. No-op for rows already on a UUID id. Returns the rewrite count.
/// Safe because FoodLog is append-only with no foreign references to its id.
@discardableResult
func migrateLegacyIds() throws -> Int {
    let legacy = try modelContext.fetch(
        FetchDescriptor<FoodLogRecord>(predicate: #Predicate { $0.id.starts(with: "fl_") })
    )
    var rewritten = 0
    for row in legacy {
        guard let entry = try? row.entry() else { continue }
        let migrated = entry.copyWith(id: FoodLogEntry.newId())
        modelContext.insert(FoodLogRecord(householdID: row.householdID, entry: migrated))
        modelContext.delete(row)
        rewritten += 1
    }
    if rewritten > 0 { try modelContext.save() }
    return rewritten
}
```

> 注:先 insert 新行再 delete 旧行,避开 `@Attribute(.unique) id` 主键的就地改值;新旧 id 不同,无唯一冲突。

- [ ] **Step 4: 跑测试确认 green** — Expected: PASS(两个断言:changed==1、again==0)。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Persistence/Repositories/FoodLogRepository.swift apps/ios/FreshPantryTests/RepositoryTests.swift
git commit -m "feat(ios): FoodLogRepository 加一次性幂等 id 迁移(fl_→UUID)"
```

---

## Task 3: 同步管线纯函数层(enum + codec + gateway 分支)

一组改动保证编译:加 `SyncEntityType.foodLogEntry` 会让 `SupabaseSyncGateway:57` 的 exhaustive switch 报缺分支(全项目唯一一处 switch over entityType),故同 task 补 gateway 分支 + codec。

**Files:**
- Modify: `apps/ios/FreshPantry/Domain/Enums.swift:124-130`
- Modify: `apps/ios/FreshPantry/Sync/RemoteRowCodec.swift`(mealPlan 入口旁)
- Modify: `apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift`(pushOperation switch + EntityCodec)
- Test: `apps/ios/FreshPantryTests/Sync/FoodLogSyncCodecTests.swift`(新)

- [ ] **Step 1: 写失败测试** — 新建 `apps/ios/FreshPantryTests/Sync/FoodLogSyncCodecTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

/// FoodLog payload-blob codec round-trips a domain entry through the Supabase
/// row shape without field loss (mirrors the meal-plan codec contract).
struct FoodLogSyncCodecTests {
    @Test func payloadRoundTripPreservesFields() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = FoodLogEntry(
            id: "11111111-1111-4111-8111-111111111111",
            name: "牛奶", category: "乳品蛋类", outcome: .wasted,
            loggedAt: t, wasExpiring: true, remoteVersion: 0
        )
        let domain = try #require(DomainJSON.valueMap(entry))
        let row = RemoteRowCodec.foodLogEntryRowForUpsert(householdID: "home", entry: domain)

        // household + payload + sync columns lifted out
        #expect(row["household_id"] == .string("home"))
        #expect(row["version"] == .int(1))                 // remoteVersion 0 → first write version 1
        guard case .object = row["payload"] else { Issue.record("payload not object"); return }

        // simulate the Supabase row coming back, then decode to domain
        var back = row
        back["id"] = .string(entry.id)                     // server echoes the uuid PK column
        let decodedMap = RemoteRowCodec.foodLogEntryRowFromJson(back)
        let decoded = try #require(DomainJSON.fromValueMap(FoodLogEntry.self, from: decodedMap))
        #expect(decoded.id == entry.id)
        #expect(decoded.name == "牛奶")
        #expect(decoded.category == "乳品蛋类")
        #expect(decoded.outcome == .wasted)
        #expect(decoded.loggedAt == t)
        #expect(decoded.wasExpiring == true)
    }
}
```

- [ ] **Step 2: 跑测试确认 red** — `xcodegen generate` 后跑;Expected: 编译失败(`foodLogEntryRowForUpsert` 未定义)。

- [ ] **Step 3a: 加 enum case** — `Enums.swift:124-130`:

```swift
enum SyncEntityType: String, Codable, Sendable, CaseIterable {
    case inventoryItem
    case shoppingItem
    case customRecipe
    case mealPlanEntry
    case foodLogEntry
    case householdConfig
}
```

- [ ] **Step 3b: 加 codec 入口** — `RemoteRowCodec.swift`,紧跟 `mealPlanEntryRowForUpsert`(:86-97)之后:

```swift
/// food_log_entries ⇄ FoodLogEntry map. Same opaque-`payload` shape as
/// meal plans — only `id` and the sync columns are real columns.
static func foodLogEntryRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
    payloadRowFromJson(row)
}

static func foodLogEntryRowForUpsert(
    householdID: String,
    entry: [String: JSONValue]
) -> [String: JSONValue] {
    payloadRowForUpsert(householdID: householdID, domain: entry)
}
```

- [ ] **Step 3c: 加 EntityCodec.foodLog** — `SupabaseSyncGateway.swift`,在 `static let mealPlan`(:335-338)之后:

```swift
static let foodLog = EntityCodec(
    rowForUpsert: { RemoteRowCodec.foodLogEntryRowForUpsert(householdID: $0, entry: $1) },
    rowFromJson: { RemoteRowCodec.foodLogEntryRowFromJson($0) }
)
```

- [ ] **Step 3d: 加 pushOperation 分支** — `SupabaseSyncGateway.swift`,在 `.mealPlanEntry` case(:86-94)之后、`switch op.entityType` 内:

```swift
case .foodLogEntry:
    switch op.operation {
    case .create, .update:
        try await pushVersionedRow(table: "food_log_entries", op: op, codec: .foodLog)
    case .delete:
        try await softDeleteRemoteRow(table: "food_log_entries", op: op)
    case .intake, .deduction, .toggleChecked:
        return
    }
```

> append-only ⇒ 正常只走 `.create` / `.delete`;`.update` 复用同一首写/版本化路径(undo 的 undelete 若出现也安全),无害保留。

- [ ] **Step 4: 跑测试确认 green** — Expected: 编译通过 + round-trip PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Domain/Enums.swift apps/ios/FreshPantry/Sync/RemoteRowCodec.swift apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift apps/ios/FreshPantryTests/Sync/FoodLogSyncCodecTests.swift apps/ios/project.yml
git commit -m "feat(ios): FoodLog 同步 codec + gateway 分支 + SyncEntityType.foodLogEntry"
```

---

## Task 4: HouseholdMergePolicy.mergeFoodLog

append-only 并集合并:远端全量 + 本地未同步且不被其他 household pending op 占用的行。

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/HouseholdMergePolicy.swift`(mealPlan 段旁)
- Test: `apps/ios/FreshPantryTests/Sync/FoodLogMergeTests.swift`(新)

- [ ] **Step 1: 写失败测试** — 新建 `apps/ios/FreshPantryTests/Sync/FoodLogMergeTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

struct FoodLogMergeTests {
    private func entry(_ id: String, remoteVersion: Int) -> FoodLogEntry {
        FoodLogEntry(id: id, name: "x", outcome: .consumed,
                     loggedAt: Date(timeIntervalSince1970: 1_700_000_000),
                     remoteVersion: remoteVersion)
    }

    @Test func mergeIsUnionOfRemoteAndLocalOnly() {
        let remote = [entry("11111111-1111-4111-8111-111111111111", remoteVersion: 3)]
        let local = [
            entry("11111111-1111-4111-8111-111111111111", remoteVersion: 3), // already remote → not re-added
            entry("22222222-2222-4222-8222-222222222222", remoteVersion: 0), // local-only → kept
        ]
        let scope = LocalUploadScope(householdID: "home", pendingOps: [])
        let merged = HouseholdMergePolicy.mergeFoodLog(remote: remote, local: local, scope: scope)
        #expect(merged.map(\.id) == [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
        ])
    }

    @Test func localOnlyGuardRejectsBlankNameAndSynced() {
        #expect(HouseholdMergePolicy.isLocalOnlyFoodLog(entry("33333333-3333-4333-8333-333333333333", remoteVersion: 0)))
        #expect(!HouseholdMergePolicy.isLocalOnlyFoodLog(entry("44444444-4444-4444-8444-444444444444", remoteVersion: 5))) // synced
        let blank = FoodLogEntry(id: "55555555-5555-4555-8555-555555555555", name: "  ", outcome: .consumed,
                                 loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!HouseholdMergePolicy.isLocalOnlyFoodLog(blank)) // blank name rejected
    }
}
```

- [ ] **Step 2: 跑测试确认 red** — Expected: FAIL(`mergeFoodLog`/`isLocalOnlyFoodLog` 未定义)。

- [ ] **Step 3a: 加 mergeFoodLog** — `HouseholdMergePolicy.swift`,在 `mergeMealPlan`(:62-75)之后:

```swift
static func mergeFoodLog(
    remote: [FoodLogEntry],
    local: [FoodLogEntry],
    scope: LocalUploadScope
) -> [FoodLogEntry] {
    merge(
        remote: remote,
        local: local,
        scope: scope,
        entityType: .foodLogEntry,
        id: { $0.id },
        isLocalOnly: isLocalOnlyFoodLog
    )
}
```

- [ ] **Step 3b: 加 isLocalOnlyFoodLog** — 在 `isLocalOnlyMealPlan`(:102-107)之后:

```swift
static func isLocalOnlyFoodLog(_ entry: FoodLogEntry) -> Bool {
    entry.remoteVersion <= 0
        && entry.deletedAt == nil
        && !entry.id.isEmpty
        && !entry.name.trimmed.isEmpty
}
```

- [ ] **Step 4: 跑测试确认 green** — Expected: 两个 `@Test` PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Sync/HouseholdMergePolicy.swift apps/ios/FreshPantryTests/Sync/FoodLogMergeTests.swift apps/ios/project.yml
git commit -m "feat(ios): HouseholdMergePolicy.mergeFoodLog(append-only 并集)"
```

---

## Task 5: RemotePantryRepository FoodLog 方法

样板接线(无独立单测,与其他实体一致由集成路径覆盖)。

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/RemotePantryRepository.swift`

- [ ] **Step 1: 加 Table 常量** — `RemotePantryRepository.swift:52-60` 的 `Table` enum 内,`mealPlanEntries` 之后:

```swift
static let foodLogEntries = "food_log_entries"
```

- [ ] **Step 2: 加 load/upsert/watch** — 分别在对应 mealPlan 方法之后:

```swift
// 跟 loadMealPlanEntries(:80-82) 之后
func loadFoodLogEntries(_ hid: String) async throws -> [[String: JSONValue]] {
    try await loadRows(from: Table.foodLogEntries, hid: hid, decode: RemoteRowCodec.foodLogEntryRowFromJson)
}

// 跟 upsertMealPlanEntries(:138-146) 之后
func upsertFoodLogEntries(_ hid: String, _ rows: [[String: JSONValue]]) async throws {
    try await upsertRows(
        into: Table.foodLogEntries,
        hid: hid,
        rows: rows,
        method: "upsertFoodLogEntries",
        encode: RemoteRowCodec.foodLogEntryRowForUpsert
    )
}

// 跟 watchMealPlanEntries(:211-215) 之后
func watchFoodLogEntries(_ hid: String) -> AsyncStream<[[String: JSONValue]]> {
    watch(table: Table.foodLogEntries, hid: hid) { [weak self] in
        try? await self?.loadFoodLogEntries(hid)
    }
}
```

- [ ] **Step 3: 跑构建确认编译** — 跑验证命令(测试套件应仍全绿,无新测试)。Expected: BUILD/TEST PASS。

- [ ] **Step 4: Commit**

```bash
git add apps/ios/FreshPantry/Sync/RemotePantryRepository.swift
git commit -m "feat(ios): RemotePantryRepository 加 food_log_entries load/upsert/watch"
```

---

## Task 6: Coordinator 接线 + 迁移调用 + AppDependencies

注入 `FoodLogRepository`;`startSync` 开头跑一次性迁移(在 `uploadLocalOnly` 前,只在有 household 时触发,无竞态);加 FoodLog 的 uploadLocalOnly / bulk pull / subscribe / applyFoodLogRows。

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift`
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift:174-183`

- [ ] **Step 1: 构造器注入** — `HouseholdContentSyncCoordinator.swift`,构造器(:40-58):参数表 `mealPlan: MealPlanRepository,` 后加 `foodLog: FoodLogRepository,`;类加存储属性 `private let foodLog: FoodLogRepository`(与 `mealPlan` 并列);init 体加 `self.foodLog = foodLog`。

- [ ] **Step 2: startSync 头部迁移 + bulk pull + apply** — `startSync`(:88-121):
  - 在 `let scope = LocalUploadScope(...)` 之前插入迁移:

```swift
// One-shot legacy-id migration so historical fl_<ms> rows can backfill into
// the uuid PK column. Idempotent — a no-op once everything is on a UUID id.
try? await foodLog.migrateLegacyIds()
guard isCurrent(gen, householdId) else { return }
```

  - bulk pull 段,`let mealPlanRows = try await remote.loadMealPlanEntries(householdId)` 后加:

```swift
let foodLogRows = try await remote.loadFoodLogEntries(householdId)
```

  - apply 段,`await applyMealPlanRows(mealPlanRows, householdId, gen)` 后加:

```swift
await applyFoodLogRows(foodLogRows, householdId, gen)
```

- [ ] **Step 3: uploadLocalOnly FoodLog 段** — `uploadLocalOnly`,mealPlan 段(:183-195)之后:

```swift
// Food log (append-only history → full backfill)
guard isCurrent(gen, householdId) else { return }
let localFoodLog = (try? await foodLog.loadAllFor(householdId)) ?? []
let uploadFoodLog = localFoodLog.filter {
    HouseholdMergePolicy.isLocalOnlyFoodLog($0) && scope.allows(.foodLogEntry, $0.id)
}
if !uploadFoodLog.isEmpty {
    try await remote.upsertFoodLogEntries(householdId, uploadFoodLog.compactMap { DomainJSON.valueMap($0) })
    guard isCurrent(gen, householdId) else { return }
    let uploaded = Set(uploadFoodLog.map(\.id))
    try? await foodLog.saveEntries(householdId, localFoodLog.map {
        uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
    })
}
```

- [ ] **Step 4: subscribe FoodLog 段** — `subscribe` 的 Task 数组(mealPlan 段 :219-223)之后加一个 Task:

```swift
Task { [remote] in
    for await rows in await remote.watchFoodLogEntries(householdId) {
        await self.applyFoodLogRows(rows, householdId, gen)
    }
},
```

- [ ] **Step 5: applyFoodLogRows** — 在 `applyMealPlanRows`(:283-301)之后:

```swift
private func applyFoodLogRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
    guard isCurrent(gen, householdId) else { return }
    // Tolerant per-row decode: FoodLogEntry decoding throws on a bad loggedAt,
    // and one malformed remote row must not abort the whole apply.
    let decoded = rows
        .compactMap { DomainJSON.fromValueMap(FoodLogEntry.self, from: $0) }
        .filter { !$0.id.isEmpty }

    let scope = LocalUploadScope(
        householdID: householdId,
        pendingOps: (try? await outbox.loadPending()) ?? []
    )
    let local = (try? await foodLog.loadAllFor(householdId)) ?? []
    let merged = HouseholdMergePolicy.mergeFoodLog(remote: decoded, local: local, scope: scope)

    guard isCurrent(gen, householdId) else { return }
    try? await foodLog.saveEntries(householdId, merged)
    await signalMerge()
}
```

- [ ] **Step 6: AppDependencies 注入** — `AppDependencies.swift:174-183` 的 `HouseholdContentSyncCoordinator(...)` 调用,`mealPlan: self.mealPlanRepository,` 后加 `foodLog: self.foodLogRepository,`。

- [ ] **Step 7: 跑构建 + 测试确认编译/全绿** — Expected: BUILD/TEST PASS(既有套件不破)。

- [ ] **Step 8: Commit**

```bash
git add apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift apps/ios/FreshPantry/App/AppDependencies.swift
git commit -m "feat(ios): HouseholdContentSyncCoordinator 接入 FoodLog 同步 + 启动 id 迁移"
```

---

## Task 7: 写入点 enqueue

3 处:`DeductionController`(做菜→consumed,create)、`InventoryStore.remove`(手动删除→create)、`InventoryStore.undoRemove`(撤销→delete 软删)。`saveEntries`/`FoodLogSeeder` 有意保持 local-only,不动。

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Recipes/DeductionController.swift`(:88-110 区)
- Modify: `apps/ios/FreshPantry/Features/Inventory/InventoryStore.swift`(:139、:160)
- Test: `apps/ios/FreshPantryTests/InventoryStoreTests.swift`

- [ ] **Step 1: 写失败测试** — `InventoryStoreTests.swift` 加(参照 :345 既有 fixture + SyncWriterTests 的 in-memory outbox 模式):

```swift
@Test func removeWithOutcomeEnqueuesFoodLogCreate() async throws {
    let container = try ModelContainerFactory.makeInMemory()
    let invRepo = InventoryRepository(modelContainer: container)
    let foodRepo = FoodLogRepository(modelContainer: container)
    let outbox = SyncOutboxRepository(modelContainer: container)
    let defaults = UserDefaults(suiteName: "test.invstore.\(UUID().uuidString)")!
    let session = SyncSession(selectedHouseholdId: "home", defaults: defaults)
    let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
    let apple = Ingredient(id: "11111111-1111-4111-8111-111111111111", name: "苹果", category: "果蔬生鲜")
    try await invRepo.saveItems("home", [apple])
    let store = InventoryStore(repository: invRepo, foodLogRepository: foodRepo, householdID: "home", syncWriter: writer)
    await store.load()

    let undo = try #require(await store.remove(apple, outcome: .wasted))

    let pending = try await outbox.loadPending()
    let foodOps = pending.filter { $0.entityType == .foodLogEntry }
    #expect(foodOps.count == 1)
    #expect(foodOps.first?.operation == .create)
    #expect(foodOps.first?.entityId == undo.loggedEntryId)

    // undo soft-deletes the logged departure
    _ = await store.undoRemove(undo)
    let afterUndo = try await outbox.loadPending()
    let deletes = afterUndo.filter { $0.entityType == .foodLogEntry && $0.operation == .delete }
    #expect(deletes.contains { $0.entityId == undo.loggedEntryId })
}
```

> `Ingredient` 构造参数以实际签名为准(取项目内既有构造用法);关键断言是 outbox 出现 `.foodLogEntry` 的 `.create` 与 `.delete`。

- [ ] **Step 2: 跑测试确认 red** — Expected: FAIL(当前 remove/undoRemove 不 enqueue foodLogEntry)。

- [ ] **Step 3a: InventoryStore.remove enqueue create** — `InventoryStore.swift`,`try? await foodLogRepository.append(householdID, entry)`(:139)之后、`await enqueueDelete(removed)` 之前插入:

```swift
// FoodLog now syncs to the household: enqueue the departure as a create.
if let patch = DomainJSON.valueMap(entry) {
    await syncWriter?.enqueue(
        entityType: .foodLogEntry,
        entityId: entry.id,
        operation: .create,
        patch: patch,
        baseVersion: entry.remoteVersion
    )
}
```

- [ ] **Step 3b: InventoryStore.undoRemove enqueue delete** — `InventoryStore.swift`,`try? await foodLogRepository.deleteEntry(householdID, undo.loggedEntryId)`(:160)之后插入:

```swift
// Mirror the local point-delete remotely (soft delete the logged departure).
if !undo.loggedEntryId.isEmpty {
    await syncWriter?.enqueue(
        entityType: .foodLogEntry,
        entityId: undo.loggedEntryId,
        operation: .delete,
        patch: [:],
        baseVersion: nil
    )
}
```

- [ ] **Step 3c: DeductionController enqueue create** — `DeductionController.swift`:把 consumed-departure append 循环(:89-98)收集成数组,并入既有 `ops` batch:
  - 循环改为收集 entries(在 `for departure in result.consumedDepartures {` 外先 `var loggedEntries: [FoodLogEntry] = []`,循环体 append 后 `loggedEntries.append(entry)`)。
  - 把 OUTBOX SEAM 注释里 `FoodLog sync stays local-only (parity with Flutter).` 一句删掉,替换为说明 FoodLog 现在也同步。
  - `let ops: [SyncWriter.PendingOp] = result.syncIntents.compactMap { ... }` 改为 `var ops`,并在 `await syncWriter?.enqueueBatch(ops)` 之前追加:

```swift
// FoodLog departures now sync to the household (append-only creates).
ops.append(contentsOf: loggedEntries.compactMap { entry in
    guard let patch = DomainJSON.valueMap(entry) else { return nil }
    return SyncWriter.PendingOp(
        entityType: .foodLogEntry,
        entityId: entry.id,
        operation: .create,
        patch: patch,
        baseVersion: entry.remoteVersion
    )
})
```

- [ ] **Step 4: 跑测试确认 green** — Expected: 新测试 PASS,既有 `DeductionFlowTests`/`InventoryStoreTests` 仍绿。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Features/Recipes/DeductionController.swift apps/ios/FreshPantry/Features/Inventory/InventoryStore.swift apps/ios/FreshPantryTests/InventoryStoreTests.swift
git commit -m "feat(ios): FoodLog 去向/撤销写入家庭同步 outbox(create/软删)"
```

---

## Task 8: Supabase migration

建 `food_log_entries`(payload-blob,照 `meal_plan_entries`)+ RLS + version trigger + realtime,并应用到生产库(幂等)。

**Files:**
- Create: `supabase/migrations/20260611120000_food_log_entries_sync.sql`

- [ ] **Step 1: 写迁移 SQL** — 新建该文件:

```sql
-- Food-log entries: household-scoped, realtime-synced, append-only.
--
-- Mirrors public.meal_plan_entries: an opaque jsonb `payload`
-- (name, category, outcome, loggedAt, wasExpiring) plus the standard sync
-- columns. Optimistic-concurrency reuses app_private.bump_row_version.
-- Append-only in the client; `deleted_at` only set when a manual removal's
-- logged departure is undone.

create table public.food_log_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  payload jsonb not null,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index food_log_entries_household_updated_idx
  on public.food_log_entries (household_id, updated_at);

grant select, insert, update, delete on public.food_log_entries to authenticated;

alter table public.food_log_entries enable row level security;

create policy "food_log_entries_member_all" on public.food_log_entries
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

drop trigger if exists food_log_entries_bump_version on public.food_log_entries;
create trigger food_log_entries_bump_version
  before update on public.food_log_entries
  for each row
  execute function app_private.bump_row_version();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'food_log_entries'
    ) then
      execute 'alter publication supabase_realtime add table public.food_log_entries';
    end if;
  end if;
end;
$$;
```

- [ ] **Step 2: 应用到生产库** — 经 Supabase MCP `apply_migration`(name: `food_log_entries_sync`,query: 上述 SQL)。先 `list_tables` 确认无同名表,再 apply。

- [ ] **Step 3: 幂等/正确性校验** — `list_tables` 确认 `food_log_entries` 存在且列/RLS 就位;`list_migrations` 含本迁移。再次 apply 同迁移应安全(表已存在则报已存在 → 说明迁移文件需 `create table if not exists`?**否**:与既有 `meal_plan_entries` 一致用裸 `create table`,迁移系统按版本号只跑一次,生产校验以 list_tables 为准)。

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260611120000_food_log_entries_sync.sql
git commit -m "feat(supabase): food_log_entries 家庭共享表(payload-blob + RLS + realtime)"
```

---

## Task 9: 全量回归 + 收尾

- [ ] **Step 1: 全量测试** — `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -30`。Expected: 全部 PASS(新增 4 类测试 + 既有套件)。

- [ ] **Step 2: 扫 diff** — 确认无遗留 `FoodLog sync stays local-only` 注释、无 `fl_` 前缀 newId、无 swallowed error(enqueue 失败不静默成功)。

- [ ] **Step 3: 实活联调说明(交用户)** — 真机/真账号 A+B 两设备验证:A 做菜/删除产生去向 → B 拉到;A 撤销 → B 该条消失;首次进家庭历史回填可见。需真实 Supabase 凭据(gitignored `Secrets.plist`),由用户触发。

- [ ] **Step 4: 视用户偏好提交方式** — 按既有约定可分维度直接推 main,或开 PR。

---

## Self-Review(写 plan 后自查)

**Spec 覆盖:** §3 决策表逐条 → Task 映射:完整回填+id 迁移=T1/T2/T6;payload-blob=T3;并集合并=T4;仅 create/delete=T3/T7;统计变全家=T6 apply 自然达成。§4 改动清单 6 节 → T1–T8 全覆盖。§5 数据流写/撤销/读/回填 → T6+T7。§6 测试计划 → 各 task TDD step。

**占位符扫描:** 无 TBD/TODO;每个改动给了完整代码块;命令含预期结果。唯一柔性处:Task 7 测试的 `Ingredient(...)` 构造参数标注「以实际签名为准」——这是诚实标注而非占位,执行者读一眼既有构造即可。

**类型一致性:** `foodLogEntryRowForUpsert`/`foodLogEntryRowFromJson`(T3)被 T5 repo、T3 EntityCodec 一致引用;`mergeFoodLog`/`isLocalOnlyFoodLog`(T4)被 T6 uploadLocalOnly/applyFoodLogRows 一致引用;`migrateLegacyIds`(T2)被 T6 startSync 调用;`.foodLogEntry` case(T3)贯穿 gateway/merge/repo/enqueue。`baseVersion: entry.remoteVersion`(create,=0)对齐 gateway 首写路径。
