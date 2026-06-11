# FoodLog 家庭同步 — 设计

> 状态:已与用户确认设计方向(2026-06-11),待写实现计划。
> 目标:让 FoodLog(食物去向/减废记录)成为最后一个参与家庭共享同步的实体,补齐家庭共享完整性。

## 1. 背景与动机

`FoodLogEntry` 是减废统计(`WasteInsightsStore`)的唯一数据源,记录每件食材的去向(`consumed`/`wasted` + `wasExpiring`)。目前它是**有意 local-only** 的,不参与家庭同步。

**Chesterton's fence 已查清** —— Flutter 旧版不同步 FoodLog 不是语义约束,而是排期判断:

- `apps/mobile/lib/providers/food_log_provider.dart:17-19` 注释明说 `household sync is a later round`;`FoodLogNotifier` 只 `with PersistenceQueue`,缺 `SyncEnqueue`(其他已同步 notifier 都有)。
- `replaceFromRemote`(`food_log_provider.dart:63-72`)已实现但 `household_content_sync_coordinator.dart` 从未调用它 —— 典型的「基础设施就绪、接线未做」。
- iOS 端同样:`DeductionController.swift:105` 注释 `FoodLog sync stays local-only (parity with Flutter)`。

推进不会破坏任何隐含设计约束。

**价值**:开启后减废统计从「本设备」变为「全家」口径,家庭成员共同看到减废成效。这是本功能的核心目的。

## 2. 目标 / 非目标

**目标**
- FoodLog 写入/撤销纳入现有离线 outbox 同步管线,与 inventory/shopping/mealPlan 同构。
- 已有本地历史去向记录**完整回填**上云(用户已确认),全家可见完整历史减废。
- 全量测试保持绿(当前基线见最新提交)。

**非目标**
- 不为 FoodLog 引入编辑能力(保持 append-only)。
- 不在云端提供 FoodLog 的结构化查询/索引(客户端拉回全量后本地算统计)。
- 不改动 `WasteInsightsStore` 的统计算法本身(只是它的输入从本设备变全家)。

## 3. 关键设计决策(已与用户确认)

| 决策 | 选择 | 理由 |
|---|---|---|
| 历史数据 | **完整回填** | 全家看到完整历史减废;代价是需一次性本地 id 迁移(下条) |
| id 格式 | 新记录 `UUID().uuidString.lowercased()`;历史 `fl_<ms>` 一次性迁移为 UUID | Supabase 主键列是 `uuid`,且 `SupabaseSyncGateway.pushVersionedRow` 对更新有 `isUuid` 校验,非 UUID 会抛 `nonUuidVersionedWrite` |
| 云端列布局 | **payload-blob**(对齐 `meal_plan_entries`,非 inventory 的显式列) | append-only + 客户端本地算统计,云端无查询/索引需求,codec 最省 |
| 合并策略 | `远端全量 ∪ 本地未同步行` | append-only ⇒ 无 field-level 3-way merge,几乎无冲突 |
| 同步 op | 仅 `create` 与 `delete`(软删) | append-only ⇒ 无 `update`;`delete` 仅用于 undo 撤销已记录的 departure |
| 统计口径 | 同步后变「全家」口径 | 即本功能目的;会改变现有 WasteInsights 数字,可接受 |

## 4. 改动清单(分层,带锚点)

> 路径相对 `apps/ios/FreshPantry/`,除 Supabase migration 外。

### 4.1 Domain — id 格式切换
- `Domain/Models/FoodLogEntry.swift:58` `newId()`:`"fl_\(...)"` → `UUID().uuidString.lowercased()`。
- 同步三件套(`remoteVersion`/`clientUpdatedAt`/`deletedAt` + `syncMetadata` + `copyWith`)已存在,model 字段不动。

### 4.2 一次性本地 id 迁移(完整回填前提)
- 新增迁移逻辑(放在 `Persistence/` 或启动装配处),扫描本地 `id` 以 `fl_` 开头的 `FoodLogRecord`,逐条重写为新 UUID(同时更新 record 的自然键与 `payloadJSON` 内 `id`)。
- **幂等无需 flag**:迁移后不再有 `fl_` 前缀,重跑即 no-op。
- FoodLog 是 append-only 纯分析数据,无任何外键指向其 id,重写安全。
- 时机:app 启动装配、在首次 `uploadLocalOnly` 之前。各设备各自迁移本地历史 → 各自回填 → 云端为全家并集(非重复,符合 append-only)。

### 4.3 同步管线接线(跟随现有实体模式)
- `Domain/Enums.swift:124-130` `SyncEntityType` 加 `case foodLogEntry`。
- `Sync/RemoteRowCodec.swift`:新增 FoodLog 的 `...RowForUpsert` / `...RowFromJson`,采用 **payload-blob**(整 domain JSON 进单 `payload` 列)。
- `Sync/MergePolicy` 体系 → `HouseholdMergePolicy`:新增 `mergeFoodLog`(远端全量 ∪ 本地 `remoteVersion <= 0` 且未被其他 household pending op 占用的行)+ `isLocalOnlyFoodLog`。
- `Sync/SupabaseSyncGateway.swift`:`pushOperation` switch 加 `.foodLogEntry` 分支;新增 `EntityCodec.foodLog`(参考 `:323-339` 现有 EntityCodec)。
- `Sync/HouseholdContentSyncCoordinator.swift`:构造器注入 `FoodLogRepository`;`startSync` 加 FoodLog 的 `uploadLocalOnly` + `push` + realtime `subscribe` + bulk pull + 新增 `applyFoodLogRows`(带代差守卫,与现有 `applyXRows` 同构)。
- `Sync/RemotePantryRepository.swift`:新增 `loadFoodLogEntries` / `upsertFoodLogEntries` / `watchFoodLogEntries` + `Table` 常量。
- `App/AppDependencies.swift`:把已有的 `foodLogRepository` 实例注入 `HouseholdContentSyncCoordinator` 构造。

### 4.4 写入点 enqueue(精确清单)
- `Features/Recipes/DeductionController.swift:98`(做菜扣减 → consumed departure):append 后对**每条** appended entry enqueue `.foodLogEntry` **create**。删除 `:105` 的 local-only 注释。
- `Features/Inventory/InventoryStore.swift:139`(手动删除 → consumed/wasted):append 后 enqueue `.foodLogEntry` **create**。
- `Features/Inventory/InventoryStore.swift:160`(`undoRemove` → `deleteEntry`):enqueue `.foodLogEntry` **delete**(软删 `undo.loggedEntryId`)。仅当 `loggedEntryId` 非空。
- **不 enqueue**:`FoodLogRepository.saveEntries`(remote apply / backup import 入口)、`FoodLogSeeder`(空 household 本地演示播种,与其他 seeder 一致保持 local-only)。

### 4.5 Supabase migration
- 新建 `supabase/migrations/<ts>_food_log_entries_sync.sql`,建 `public.food_log_entries`(payload-blob 变体):
  - 列:`id uuid pk`、`household_id uuid not null references households(id) on delete cascade`、`payload jsonb not null`、`version int not null default 1`、`client_id text`、`client_updated_at timestamptz`、`created_at`/`updated_at timestamptz default now()`、`deleted_at timestamptz`。
  - RLS:`enable row level security` + `for all to authenticated using/with check (app_private.is_household_member(household_id))`。
  - version 自增触发器:`before update ... execute app_private.bump_row_version()`(对齐 `20260607120000_meal_plan_entries_sync.sql`)。
  - 加入 `supabase_realtime` publication(幂等 guard,对齐现有 migration)。
  - `grant select, insert, update, delete ... to authenticated`。
- 按项目惯例**应用到生产库**(幂等),与 `20260610153740_inventory_items_tags.sql` 同流程。

## 5. 数据流

**写(本地 → 云)**
1. 用户做菜扣减 / 手动删除带 outcome → `FoodLogRepository.append`(本地落库,id 为新 UUID)。
2. 写入点 enqueue `.foodLogEntry` create op → `SyncWriter.enqueueBatch`(`selectedHouseholdId` 为空时整批 no-op,保持单机本地模式)。
3. `SyncCoordinator` drain outbox → `SupabaseSyncGateway` payload-blob upsert(首写 `version=1`,`ignoreDuplicates`)。

**撤销**
- `undoRemove` 本地 `deleteEntry` + enqueue `.foodLogEntry` delete → gateway 软删(写 `deleted_at`)。

**读(云 → 本地)**
- `HouseholdContentSyncCoordinator` realtime 事件 / bulk pull → `RemotePantryRepository.loadFoodLogEntries` → `applyFoodLogRows` → `HouseholdMergePolicy.mergeFoodLog`(并集)→ `FoodLogRepository.saveEntries` replace-in-scope → `session.bumpDataRevision()` → `WasteInsightsStore` reload(自动变全家口径)。

**首次进家庭(回填)**
- id 迁移(4.2)已把历史记录变 UUID → `uploadLocalOnly` 把 `remoteVersion <= 0` 的本地 FoodLog 全量推上、标 `remoteVersion = 1`。

## 6. 测试计划
- **id 迁移**:`fl_<ms>` → UUID 重写正确(自然键 + payload 内 id 一致)、幂等(二次跑 no-op)、UUID 记录不动。
- **mergeFoodLog**:远端 ∪ 本地未同步并集;被其他 household pending 占用的本地行不混入;软删 tombstone 正确剔除。
- **codec round-trip**:FoodLogEntry → payload-blob → FoodLogEntry 字段无损(含 `loggedAt` 时间编码、`outcome`、`wasExpiring`)。
- **gateway 分支**:`.foodLogEntry` create(首写 version=1)/ delete(软删)走对路径(stub URLProtocol,无需真实 key)。
- **enqueue 点**:DeductionController 多条 append 各 enqueue create;InventoryStore remove → create、undoRemove → delete;无 household 时整批 no-op。
- **统计口径**:apply 远端 FoodLog 后 `WasteInsightsStore` 反映全家数据。

## 7. 风险 / 取舍
- **统计口径变全家**:刻意;会改变现有 WasteInsights 数字。
- **多设备各自迁移历史**:各设备独立历史并集上云,非重复,符合 append-only。
- **payload-blob**:若将来需云端按 `outcome`/`logged_at` 查询,需改显式列;当前无此需求(YAGNI)。
- **id 迁移在启动跑**:仅一次(幂等),数据量小(本地 FoodLog 为减废记录,规模有限),启动开销可忽略。
- **实活联调**:需真实 Supabase URL/Key(gitignored `Secrets.plist`,仅用户可提供);开发期以 build + 单测验证,真机/真账号联调由用户触发。

## 8. 验证流程
`apps/ios` 下:新文件后 `xcodegen generate` → `xcodebuild build-for-testing` + `test`(已有模拟器 UDID)。Supabase migration 经 MCP 应用并幂等校验。
