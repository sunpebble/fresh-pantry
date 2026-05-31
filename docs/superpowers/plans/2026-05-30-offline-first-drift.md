# Offline-First (Drift 迁移 + 同步闭环) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本地存储从 SharedPreferences JSON blob 迁到 Drift(SQLite)，实现按 household 作用域的结构化持久化、增量读写与可迁移 schema，并补齐离线同步闭环(重连/回前台/重试自动 flush)、同步状态可视化与 WorkManager 后台同步。

**Architecture:** 保留现有「本地优先」分层(Riverpod root Notifier + `SyncEnqueue` outbox + version 乐观并发 + Supabase Realtime 拉取)。仅替换两处接缝：①持久化从 `StorageAdapter`(KV blob) 换成 Drift `AppDatabase`；②push 入口 `syncPushPendingProvider` 之外新增 connectivity/lifecycle/WorkManager 三个触发源。每张实体表用「索引列 + `payloadJson`(模型自带 `toJson()`)」混合方案，使模型的 `fromJson/toJson` 仍是唯一序列化事实源(DRY)，同时支持按 `household_id` / 软删除 / 到期等 SQL 查询。

**Tech Stack:** Flutter 3.10 / Dart 3.10、`flutter_riverpod ^3.3`、`drift ^2.33` + `drift_flutter ^0.3` + `drift_dev`/`build_runner`、`connectivity_plus`、`workmanager`、`supabase_flutter ^2.12`、既有 `uuid`/`shared_preferences`(settings 保留)。

---

## Context & Current State (读这一段再动手)

- 状态管理：root 级 `NotifierProvider`(`apps/mobile/lib/providers/inventory_provider.dart` 等)。Notifier 混入 `SyncEnqueue`(`apps/mobile/lib/sync/sync_enqueue.dart`) + `PersistenceQueue`(`apps/mobile/lib/providers/_persistence_queue.dart`)。
- `InventoryNotifier.build()` 是**同步**的，直接 `_repo.loadAll()`(`inventory_provider.dart:67-70`)。Shopping/CustomRecipe 同构。**Drift 读是异步**，所以沿用现有「`main.dart` 预读 → seed override 注入」模式保持 `build()` 同步契约(见 Task 8)。
- 持久化接缝：repo 依赖 `StorageAdapter`(`apps/mobile/lib/storage/storage_adapter.dart`)，生产 `SharedPrefsStorageAdapter`，测试 `InMemoryStorageAdapter`。DI 在 `apps/mobile/lib/providers/storage_service_provider.dart`，且 `main.dart` 直接 `new` repo 后 `overrideWithValue` 注入。
- 当前 4 个持久化 key：`inventory_items` / `shopping_items` / `custom_recipes` / `sync_outbox_v1`。另有 `add_history`(InventoryRepo 内的本地 Map，频次记忆，**不参与同步**)。
- repo 公共方法(必须保持以缩小 blast radius)：
  - `InventoryRepo`: `loadAll()`, `saveItems(list)`, `loadHistory()`, `saveHistory(map)`, `clearHistory()`, `hydrate(seed)`。
  - `ShoppingRepo`: `loadAll()`, `saveItems(list)`, `hydrate(seed)`。
  - `CustomRecipeRepo`: `loadAll()`, `saveRecipes(list)`, `hydrate(seed)`。
  - `SyncOutboxRepo`: `loadPending()`, `enqueue(op)`, `removeAcknowledged(ids)`, `replaceAll(ops)`。
- 同步：`SyncCoordinator.pushPending()`(`apps/mobile/lib/sync/sync_coordinator.dart`) 合并并发、读 outbox、`pushOperations`、删已 ACK；失败即停。冲突在 `apps/mobile/lib/sync/remote_pantry_repository.dart`(version 乐观并发)。
- 拉取/实时/local-only 上传：`apps/mobile/lib/sync/household_content_sync.dart` 在 household 变化时跑 `_uploadLocalOnlyContent` → push → 订阅 Realtime → 全量拉取合并 → `replaceFromRemote`。
- 远端 schema(`supabase/migrations/20260527071301_init_family_sync_schema.sql`)：三表均含 `household_id uuid not null`、`version int`、`client_updated_at`、`deleted_at`。本地表对照镜像(本地 `household_id` 允许空串 = local-only)。
- 模型同步元数据：`Ingredient`/`ShoppingItem`/`Recipe` 各带 `remoteVersion`(默认 0)、`clientUpdatedAt`、`deletedAt`，均有 `toJson/fromJson/copyWith`。
- **决策(已与用户确认)**：DB=Drift；现在就加 `household_id` 列并按其作用域读写(交付离线多 household 缓存)；提交生成的 `*.g.dart`；本轮一次做完 Phase 0-7。
- **范围边界(YAGNI)**：settings/缓存类(`ai_settings`/`reminder_settings`/`favorite_recipes`/`food_details`/`recipe_search`)留在 SharedPreferences，不迁移；`add_history` 跟随 InventoryRepo 进 Drift(本地、非同步)；不做 CRDT/字段级合并(沿用 version 乐观并发)。

## File Structure (决策锁定)

**新增**
- `apps/mobile/lib/storage/drift/app_database.dart` — Drift 库 + 4 张表定义 + 迁移策略。
- `apps/mobile/lib/storage/drift/app_database.g.dart` — build_runner 生成(提交)。
- `apps/mobile/lib/storage/drift/entity_row_codec.dart` — 模型 ↔ Drift companion/row 编解码(基于模型 `toJson/fromJson`)。
- `apps/mobile/lib/storage/blob_to_drift_migration.dart` — 一次性 prefs→Drift 导入(幂等)。
- `apps/mobile/lib/sync/sync_retry_policy.dart` — 退避策略 + 瞬时/永久错误判定。
- `apps/mobile/lib/sync/sync_flush_coordinator.dart` — connectivity + AppLifecycle 触发 flush 的 widget。
- `apps/mobile/lib/providers/connectivity_provider.dart` — connectivity 流封装(可注入测试假流)。
- `apps/mobile/lib/providers/sync_status_provider.dart` — `{online, pendingCount}` 派生状态。
- `apps/mobile/lib/widgets/common/sync_status_banner.dart` — 离线/待同步轻量提示。
- `apps/mobile/lib/sync/background_sync.dart` — WorkManager headless 回调 + 复用的纯 push 逻辑。
- 对应 `apps/mobile/test/...` 测试文件(每 Task 指明)。

**修改**
- `apps/mobile/pubspec.yaml`、`apps/mobile/lib/providers/storage_service_provider.dart`、`apps/mobile/lib/storage/inventory_repo.dart`、`shopping_repo.dart`、`custom_recipe_repo.dart`、`apps/mobile/lib/sync/sync_outbox_repo.dart`、`apps/mobile/lib/sync/sync_coordinator.dart`、`apps/mobile/lib/main.dart`、`apps/mobile/lib/app.dart`、以及受 seam 改动影响的既有测试。

## 全局约定

- 所有命令在仓库根目录执行；测试用 `cd apps/mobile && flutter test test/<...>`，codegen 用 `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`。
- 仅格式化你**实际改动**的文件(repo 早于 tall-style，勿全量 reformat)。
- 每个 Task 末尾 commit。Conventional Commits。
- 本地 `householdId` 语义：`''`(空串) = local-only(未选 household)。表行用 `household_id` 标记；按 active household 作用域读写；local-only 行在加入 household 时由既有 `_uploadLocalOnlyContent` 流程改写为该 household(本计划在 repo 层提供 `saveItems(householdId, ...)` 支持，行为与今日等价：切换后该 household 看到这些行)。

---

## Task 0: 加依赖 + build_runner 跑通

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: 加依赖**

在 `dependencies:` 增加：
```yaml
  drift: ^2.33.0
  drift_flutter: ^0.3.1
  path_provider: ^2.1.4
  connectivity_plus: ^7.0.0
  workmanager: ^0.9.0+3
```
在 `dev_dependencies:` 增加：
```yaml
  drift_dev: ^2.33.0
  build_runner: ^2.4.13
```

- [ ] **Step 2: 取依赖**

Run: `cd apps/mobile && flutter pub get`
Expected: `Got dependencies!`，无版本冲突。若 `workmanager`/`connectivity_plus` 与 SDK 报不兼容，运行 `flutter pub get` 输出里建议的最近可用版本并回填。

- [ ] **Step 3: 占位数据库让 codegen 跑通**

Create `apps/mobile/lib/storage/drift/app_database.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class _Bootstrap extends Table {
  IntColumn get id => integer().autoIncrement()();
}

@DriftDatabase(tables: [_Bootstrap])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'fresh_pantry',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
```

- [ ] **Step 4: 生成 + 分析**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: 生成 `app_database.g.dart`，`Succeeded`。
Run: `cd apps/mobile && flutter analyze lib/storage/drift/`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/storage/drift/app_database.dart apps/mobile/lib/storage/drift/app_database.g.dart
git commit -m "build(mobile): add drift, connectivity_plus, workmanager deps + drift bootstrap"
```

---

## Task 1: Drift 表定义 (schema v1，含 household_id)

**Files:**
- Modify: `apps/mobile/lib/storage/drift/app_database.dart`
- Test: `apps/mobile/test/storage/drift/app_database_test.dart`

> 设计：每表 = 索引/查询列 + `payloadJson`(模型 `toJson()` 的 JSON 文本)。`id` 为主键；`householdId` 默认 `''`。软删除以 `deletedAt`(epoch ms，nullable) 表达，便于 SQL 过滤；`remoteVersion` 便于识别 local-only(`<=0`)。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/drift/app_database_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('inventory round-trips by household scope', () async {
    await db.into(db.inventoryItems).insert(
          InventoryItemsCompanion.insert(
            id: 'a',
            householdId: const Value('h1'),
            name: '牛奶',
            payloadJson: '{"id":"a","name":"牛奶"}',
            remoteVersion: const Value(0),
          ),
        );
    final rows = await (db.select(db.inventoryItems)
          ..where((t) => t.householdId.equals('h1')))
        .get();
    expect(rows.single.name, '牛奶');
    expect(rows.single.payloadJson, contains('牛奶'));
  });

  test('outbox orders by createdAt ascending', () async {
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
        id: 'op2', householdId: 'h1', entityType: 'inventoryItem',
        entityId: 'a', operation: 'create', clientId: 'c',
        createdAt: DateTime.utc(2026, 1, 2), payloadJson: '{}'));
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
        id: 'op1', householdId: 'h1', entityType: 'inventoryItem',
        entityId: 'a', operation: 'update', clientId: 'c',
        createdAt: DateTime.utc(2026, 1, 1), payloadJson: '{}'));
    final ops = await (db.select(db.syncOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    expect(ops.map((o) => o.id), ['op1', 'op2']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/drift/app_database_test.dart`
Expected: 编译失败 — `inventoryItems`/`syncOutbox` 等未定义。

- [ ] **Step 3: 定义表，替换 `_Bootstrap`**

把 `app_database.dart` 表部分替换为：
```dart
class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get storageArea => text().nullable()();
  IntColumn get expiryDate => integer().nullable()(); // epoch ms
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()(); // epoch ms
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class ShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class CustomRecipes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get clientId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get payloadJson => text()(); // SyncOperation.toJson()
  @override
  Set<Column> get primaryKey => {id};
}

class AddHistoryEntries extends Table {
  TextColumn get name => text()();      // 频次记忆 key
  TextColumn get payloadJson => text()(); // {count,category,storage,unit}
  @override
  Set<Column> get primaryKey => {name};
}
```
更新注解与索引：
```dart
@DriftDatabase(tables: [
  InventoryItems, ShoppingItems, CustomRecipes, SyncOutbox, AddHistoryEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX IF NOT EXISTS inventory_household_idx '
            'ON inventory_items (household_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS shopping_household_idx '
            'ON shopping_items (household_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS recipes_household_idx '
            'ON custom_recipes (household_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS outbox_created_idx '
            'ON sync_outbox (created_at)',
          );
        },
      );
  // _open() 同 Task 0
```

- [ ] **Step 4: 重新生成并测试**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && flutter test test/storage/drift/app_database_test.dart`
Expected: 生成成功；2 个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/drift/ apps/mobile/test/storage/drift/
git commit -m "feat(storage): define drift schema for inventory/shopping/recipes/outbox"
```

---

## Task 2: 实体编解码 (模型 ↔ Drift)

**Files:**
- Create: `apps/mobile/lib/storage/drift/entity_row_codec.dart`
- Test: `apps/mobile/test/storage/drift/entity_row_codec_test.dart`

> DRY：序列化仍走模型自带 `toJson/fromJson`，codec 只负责拼装索引列 + payloadJson。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/drift/entity_row_codec_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/storage/drift/entity_row_codec.dart';

void main() {
  test('ingredient companion carries scope + payload, round-trips', () {
    final item = Ingredient(
      id: 'a', name: '牛奶', quantity: '1', unit: '盒', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      storage: IconType.fridge, expiryDate: DateTime.utc(2026, 6, 1),
      remoteVersion: 2,
    );
    final c = inventoryCompanionFor('h1', item);
    expect(c.id.value, 'a');
    expect(c.householdId.value, 'h1');
    expect(c.remoteVersion.value, 2);
    expect(c.expiryDate.value, DateTime.utc(2026, 6, 1).millisecondsSinceEpoch);

    final back = ingredientFromPayload(c.payloadJson.value);
    expect(back, item);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/drift/entity_row_codec_test.dart`
Expected: 编译失败 — codec 函数未定义。

- [ ] **Step 3: 实现 codec**

Create `apps/mobile/lib/storage/drift/entity_row_codec.dart`:
```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../../models/shopping_item.dart';
import '../../sync/sync_operation.dart';
import 'app_database.dart';

int? _epochMs(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

// --- Inventory ---
InventoryItemsCompanion inventoryCompanionFor(String householdId, Ingredient i) {
  return InventoryItemsCompanion.insert(
    id: i.id,
    householdId: Value(householdId),
    name: Value(i.name),
    storageArea: Value(i.storage.name),
    expiryDate: Value(_epochMs(i.expiryDate)),
    remoteVersion: Value(i.remoteVersion),
    deletedAt: Value(_epochMs(i.deletedAt)),
    payloadJson: jsonEncode(i.toJson()),
  );
}

Ingredient ingredientFromPayload(String payloadJson) =>
    Ingredient.fromJson(jsonDecode(payloadJson) as Map<String, dynamic>);

Ingredient ingredientFromRow(InventoryItem row) =>
    ingredientFromPayload(row.payloadJson);

// --- Shopping ---
ShoppingItemsCompanion shoppingCompanionFor(String householdId, ShoppingItem s) {
  return ShoppingItemsCompanion.insert(
    id: s.id,
    householdId: Value(householdId),
    name: Value(s.name),
    isChecked: Value(s.isChecked),
    remoteVersion: Value(s.remoteVersion),
    deletedAt: Value(_epochMs(s.deletedAt)),
    payloadJson: jsonEncode(s.toJson()),
  );
}

ShoppingItem shoppingFromRow(ShoppingItemData row) =>
    ShoppingItem.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);

// --- Custom recipe ---
CustomRecipesCompanion recipeCompanionFor(String householdId, Recipe r) {
  return CustomRecipesCompanion.insert(
    id: r.id,
    householdId: Value(householdId),
    name: Value(r.name),
    remoteVersion: Value(r.remoteVersion),
    deletedAt: Value(_epochMs(r.deletedAt)),
    payloadJson: jsonEncode(r.toJson()),
  );
}

Recipe recipeFromRow(CustomRecipe row) =>
    Recipe.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);

// --- Outbox ---
SyncOutboxCompanion outboxCompanionFor(SyncOperation op) {
  return SyncOutboxCompanion.insert(
    id: op.id,
    householdId: op.householdId,
    entityType: op.entityType.name,
    entityId: op.entityId,
    operation: op.operation.name,
    baseVersion: Value(op.baseVersion),
    clientId: op.clientId,
    createdAt: op.createdAt,
    payloadJson: jsonEncode(op.toJson()),
  );
}

SyncOperation outboxFromRow(SyncOutboxData row) =>
    SyncOperation.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);
```

> 注：生成的 row 数据类名以 Drift 规则推导(`InventoryItem`、`ShoppingItemData`、`CustomRecipe`、`SyncOutboxData`)。若生成名不同，以 `app_database.g.dart` 实际类名为准修正 import 处签名。

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/storage/drift/entity_row_codec_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/drift/entity_row_codec.dart apps/mobile/test/storage/drift/entity_row_codec_test.dart
git commit -m "feat(storage): add drift row codec backed by model toJson/fromJson"
```

---

## Task 3: InventoryRepo 改 Drift (保持公共 API + household 作用域)

**Files:**
- Modify: `apps/mobile/lib/storage/inventory_repo.dart`
- Test: `apps/mobile/test/storage/inventory_repo_drift_test.dart`

> 关键：保持 `loadAll/saveItems/loadHistory/saveHistory/clearHistory/hydrate` 名称；新增 `householdId` 入参以作用域读写。`saveItems(householdId, items)` = 事务内「删除该 household 的行 → 批量 upsert」，保证 disk 与 state 不漂移。`loadAll` 仍同步返回(从 hydrate 的 seed)；新增 `loadAllFor(householdId)` 异步供预读/切换。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/inventory_repo_drift_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

Ingredient _ing(String id, String name, {int v = 0}) => Ingredient(
      id: id, name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh, remoteVersion: v,
    );

void main() {
  late AppDatabase db;
  late InventoryRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepo(db);
  });
  tearDown(() => db.close());

  test('saveItems then loadAllFor is scoped by household', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶')]);
    await repo.saveItems('h2', [_ing('b', '鸡蛋')]);
    expect((await repo.loadAllFor('h1')).map((e) => e.name), ['牛奶']);
    expect((await repo.loadAllFor('h2')).map((e) => e.name), ['鸡蛋']);
  });

  test('saveItems replaces the scope, not other households', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶'), _ing('c', '面包')]);
    await repo.saveItems('h2', [_ing('b', '鸡蛋')]);
    await repo.saveItems('h1', [_ing('a', '牛奶')]); // 删除 c
    expect((await repo.loadAllFor('h1')).map((e) => e.id), ['a']);
    expect((await repo.loadAllFor('h2')).map((e) => e.id), ['b']);
  });

  test('add history persists and round-trips', () async {
    await repo.saveHistory({'牛奶': {'count': 3, 'unit': '盒'}});
    expect(repo.loadHistory()['牛奶'], {'count': 3, 'unit': '盒'});
    await repo.clearHistory();
    expect(repo.loadHistory(), isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/inventory_repo_drift_test.dart`
Expected: 编译失败 — `InventoryRepo(AppDatabase)`、`loadAllFor`、`saveItems(householdId, ...)` 未定义。

- [ ] **Step 3: 重写 InventoryRepo**

替换 `apps/mobile/lib/storage/inventory_repo.dart` 全文：
```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/ingredient.dart';
import '../utils/ingredient_normalizer.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

class InventoryRepo {
  InventoryRepo(this._db);

  final AppDatabase _db;
  List<Ingredient>? _hydratedSeed;
  Map<String, dynamic> _history = const {};

  /// 预读种子(main.dart 预读注入)，保持 Notifier.build() 同步契约。
  void hydrate(List<Ingredient> seed) => _hydratedSeed = seed;

  /// 同步取一次种子；无种子时返回空(切换 household 走异步 loadAllFor)。
  List<Ingredient> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  /// 按 household 作用域异步读取(并按现有规则归一化)。
  Future<List<Ingredient>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final items = <Ingredient>[];
    for (final row in rows) {
      try {
        items.add(normalizeInventoryIngredient(ingredientFromRow(row)));
      } catch (_) {
        // 跳过单条坏数据，保留其余。
      }
    }
    return items;
  }

  /// 事务内替换该 household 的全部行(删除 + 批量 upsert)。
  Future<void> saveItems(String householdId, List<Ingredient> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.inventoryItems)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.inventoryItems,
          items.map((i) => inventoryCompanionFor(householdId, i)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  // --- add_history (本地频次记忆，非同步) ---
  Map<String, dynamic> loadHistory() => _history;

  /// 预读 history 到内存(main.dart 调用)。
  Future<void> hydrateHistory() async {
    final rows = await _db.select(_db.addHistoryEntries).get();
    _history = {
      for (final r in rows) r.name: jsonDecode(r.payloadJson),
    };
  }

  Future<void> saveHistory(Map<String, dynamic> history) async {
    _history = Map<String, dynamic>.from(history);
    await _db.transaction(() async {
      await _db.delete(_db.addHistoryEntries).go();
      await _db.batch((b) {
        b.insertAll(
          _db.addHistoryEntries,
          history.entries.map(
            (e) => AddHistoryEntriesCompanion.insert(
              name: e.key,
              payloadJson: jsonEncode(e.value),
            ),
          ),
        );
      });
    });
  }

  Future<void> clearHistory() => saveHistory(const {});
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/storage/inventory_repo_drift_test.dart`
Expected: 3 测试 PASS。

> 注：`loadHistory()` 现返回内存缓存，需 `hydrateHistory()` 预读(Task 8 在 main.dart 调用，`_AddHistoryNotifier.build()` 仍同步可用)。`saveHistory` 在 `record()` 中已 `await`，无回归。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/inventory_repo.dart apps/mobile/test/storage/inventory_repo_drift_test.dart
git commit -m "feat(storage): back InventoryRepo with drift, household-scoped"
```

---

## Task 4: ShoppingRepo 改 Drift

**Files:**
- Modify: `apps/mobile/lib/storage/shopping_repo.dart`
- Test: `apps/mobile/test/storage/shopping_repo_drift_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/shopping_repo_drift_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';

ShoppingItem _s(String id, String name) =>
    ShoppingItem(id: id, name: name, detail: '', category: '其他');

void main() {
  late AppDatabase db;
  late ShoppingRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ShoppingRepo(db);
  });
  tearDown(() => db.close());

  test('saveItems scoped + dedup on load', () async {
    await repo.saveItems('h1', [_s('a', '牛奶'), _s('b', '牛奶')]);
    final loaded = await repo.loadAllFor('h1');
    expect(loaded.length, 1); // deduplicateShoppingItems 生效
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/shopping_repo_drift_test.dart`
Expected: 编译失败。

- [ ] **Step 3: 重写 ShoppingRepo**

替换 `apps/mobile/lib/storage/shopping_repo.dart` 全文：
```dart
import 'package:drift/drift.dart';

import '../models/shopping_item.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';
import 'shopping_item_normalizer.dart';

class ShoppingRepo {
  ShoppingRepo(this._db);

  final AppDatabase _db;
  List<ShoppingItem>? _hydratedSeed;

  void hydrate(List<ShoppingItem> seed) => _hydratedSeed = seed;

  List<ShoppingItem> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  Future<List<ShoppingItem>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.shoppingItems)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final items = <ShoppingItem>[];
    for (final row in rows) {
      try {
        items.add(normalizeShoppingItemCategory(shoppingFromRow(row)));
      } catch (_) {
        // skip malformed
      }
    }
    return deduplicateShoppingItems(items);
  }

  Future<void> saveItems(String householdId, List<ShoppingItem> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.shoppingItems)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.shoppingItems,
          items.map((s) => shoppingCompanionFor(householdId, s)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/storage/shopping_repo_drift_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/shopping_repo.dart apps/mobile/test/storage/shopping_repo_drift_test.dart
git commit -m "feat(storage): back ShoppingRepo with drift, household-scoped"
```

---

## Task 5: CustomRecipeRepo 改 Drift

**Files:**
- Modify: `apps/mobile/lib/storage/custom_recipe_repo.dart`
- Test: `apps/mobile/test/storage/custom_recipe_repo_drift_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/custom_recipe_repo_drift_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';

void main() {
  late AppDatabase db;
  late CustomRecipeRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CustomRecipeRepo(db);
  });
  tearDown(() => db.close());

  test('saveRecipes round-trips scoped; blank id/name skipped on load',
      () async {
    final ok = Recipe(id: 'r1', name: '番茄炒蛋', ingredients: const [], steps: const []);
    await repo.saveRecipes('h1', [ok]);
    final loaded = await repo.loadAllFor('h1');
    expect(loaded.map((r) => r.name), ['番茄炒蛋']);
  });
}
```
> 若 `Recipe` 构造必填项不同，按 `apps/mobile/lib/models/recipe.dart` 的实际签名补齐最小字段。

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/custom_recipe_repo_drift_test.dart`
Expected: 编译失败。

- [ ] **Step 3: 重写 CustomRecipeRepo**

替换 `apps/mobile/lib/storage/custom_recipe_repo.dart` 全文：
```dart
import 'package:drift/drift.dart';

import '../models/recipe.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

class CustomRecipeRepo {
  CustomRecipeRepo(this._db);

  final AppDatabase _db;
  List<Recipe>? _hydratedSeed;

  void hydrate(List<Recipe> seed) => _hydratedSeed = seed;

  List<Recipe> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  Future<List<Recipe>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.customRecipes)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final recipes = <Recipe>[];
    for (final row in rows) {
      try {
        final recipe = recipeFromRow(row);
        if (recipe.id.isNotEmpty && recipe.name.isNotEmpty) recipes.add(recipe);
      } catch (_) {
        // skip malformed
      }
    }
    return recipes;
  }

  Future<void> saveRecipes(String householdId, List<Recipe> recipes) {
    return _db.transaction(() async {
      await (_db.delete(_db.customRecipes)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.customRecipes,
          recipes.map((r) => recipeCompanionFor(householdId, r)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/storage/custom_recipe_repo_drift_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/custom_recipe_repo.dart apps/mobile/test/storage/custom_recipe_repo_drift_test.dart
git commit -m "feat(storage): back CustomRecipeRepo with drift, household-scoped"
```

---

## Task 6: SyncOutboxRepo 改 Drift

**Files:**
- Modify: `apps/mobile/lib/sync/sync_outbox_repo.dart`
- Test: `apps/mobile/test/sync/sync_outbox_repo_drift_test.dart`

> 保持 `loadPending()`(同步) / `enqueue` / `removeAcknowledged` / `replaceAll`。`loadPending()` 现从内存缓存读(由 `hydratePending()` 预读)，因为 `SyncEnqueue.enqueueSync` 与 `household_content_sync` 都同步调用 `loadPending()`。每次写后刷新缓存。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/sync/sync_outbox_repo_drift_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

SyncOperation _op(String id) => SyncOperation(
      id: id, householdId: 'h1', entityType: SyncEntityType.inventoryItem,
      entityId: 'a', operation: SyncOperationType.create, patch: const {},
      clientId: 'c', createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late AppDatabase db;
  late SyncOutboxRepo repo;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SyncOutboxRepo(db);
    await repo.hydratePending();
  });
  tearDown(() => db.close());

  test('enqueue persists and loadPending (sync) reflects it', () async {
    await repo.enqueue(_op('op1'));
    expect(repo.loadPending().map((o) => o.id), ['op1']);
  });

  test('removeAcknowledged drops only acked', () async {
    await repo.enqueue(_op('op1'));
    await repo.enqueue(_op('op2'));
    await repo.removeAcknowledged({'op1'});
    expect(repo.loadPending().map((o) => o.id), ['op2']);
  });

  test('survives a fresh repo over same db (true persistence)', () async {
    await repo.enqueue(_op('op1'));
    final repo2 = SyncOutboxRepo(db);
    await repo2.hydratePending();
    expect(repo2.loadPending().map((o) => o.id), ['op1']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/sync/sync_outbox_repo_drift_test.dart`
Expected: 编译失败。

- [ ] **Step 3: 重写 SyncOutboxRepo**

替换 `apps/mobile/lib/sync/sync_outbox_repo.dart` 全文：
```dart
import 'package:drift/drift.dart';

import '../storage/drift/app_database.dart';
import '../storage/drift/entity_row_codec.dart';
import 'sync_operation.dart';

class SyncOutboxRepo {
  SyncOutboxRepo(this._db);

  final AppDatabase _db;
  List<SyncOperation> _cache = const [];

  /// 预读 outbox 到内存(main.dart / 测试 setUp 调用)。
  Future<void> hydratePending() async {
    _cache = await _readAll();
  }

  /// 同步读取(供 enqueueSync / household_content_sync 的同步路径)。
  List<SyncOperation> loadPending() => _cache;

  Future<void> enqueue(SyncOperation operation) async {
    await _db.into(_db.syncOutbox).insertOnConflictUpdate(
          outboxCompanionFor(operation),
        );
    _cache = await _readAll();
  }

  Future<void> removeAcknowledged(Set<String> operationIds) async {
    if (operationIds.isEmpty) return;
    await (_db.delete(_db.syncOutbox)
          ..where((t) => t.id.isIn(operationIds)))
        .go();
    _cache = await _readAll();
  }

  Future<void> replaceAll(List<SyncOperation> operations) async {
    await _db.transaction(() async {
      await _db.delete(_db.syncOutbox).go();
      await _db.batch((b) {
        b.insertAll(_db.syncOutbox, operations.map(outboxCompanionFor));
      });
    });
    _cache = await _readAll();
  }

  Future<List<SyncOperation>> _readAll() async {
    final rows = await (_db.select(_db.syncOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    final ops = <SyncOperation>[];
    for (final row in rows) {
      try {
        ops.add(outboxFromRow(row));
      } catch (_) {
        // skip malformed op
      }
    }
    return ops;
  }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/sync/sync_outbox_repo_drift_test.dart`
Expected: 3 测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/sync/sync_outbox_repo.dart apps/mobile/test/sync/sync_outbox_repo_drift_test.dart
git commit -m "feat(sync): back SyncOutboxRepo with drift, sync-read via in-memory cache"
```

---

## Task 7: Notifier 作用域写入对齐 (saveItems 加 householdId)

**Files:**
- Modify: `apps/mobile/lib/providers/inventory_provider.dart`(`_save`)
- Modify: `apps/mobile/lib/providers/shopping_provider.dart`(`_save`)
- Modify: `apps/mobile/lib/providers/custom_recipe_provider.dart`(`_save`)
- Test: `apps/mobile/test/providers/inventory_scope_save_test.dart`

> Notifier 的 `_save` 现在要带 active household。`SyncEnqueue` 已有 `_householdId`(私有)。新增 protected getter `activeHouseholdId` 暴露给 Notifier。

- [ ] **Step 1: 在 SyncEnqueue 暴露 household**

`apps/mobile/lib/sync/sync_enqueue.dart` 把私有改为受保护可读：
```dart
  /// The household this notifier currently syncs to, or empty when local-only.
  @protected
  String get activeHouseholdId => ref.read(selectedHouseholdIdProvider).trim();

  String get _householdId => activeHouseholdId;
```
(顶部确保 `import 'package:flutter/foundation.dart';`)

- [ ] **Step 2: 写失败测试**

Create `apps/mobile/test/providers/inventory_scope_save_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  test('add writes under active household scope', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = InventoryRepo(db);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      inventoryRepoProvider.overrideWithValue(repo),
      selectedHouseholdIdProvider.overrideWithValue('h1'),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(inventoryProvider.notifier).add(
          Ingredient(
            id: '', name: '牛奶', quantity: '1', unit: '盒', imageUrl: '',
            freshnessPercent: 1, state: FreshnessState.fresh,
          ),
        );

    expect((await repo.loadAllFor('h1')).map((e) => e.name), ['牛奶']);
    expect(await repo.loadAllFor('h2'), isEmpty);
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd apps/mobile && flutter test test/providers/inventory_scope_save_test.dart`
Expected: 失败 — `_save` 仍调用旧的 `saveItems(items)`(参数不符) 或 `appDatabaseProvider` 未定义(Task 8 提供；本 Task 先只改 `_save`，该测试在 Task 8 完成后转绿——若顺序执行，可将本测试标 `skip` 直到 Task 8)。

- [ ] **Step 4: 改三个 Notifier 的 `_save`**

`inventory_provider.dart`:
```dart
  Future<void> _save(List<Ingredient> items) async {
    await _repo.saveItems(activeHouseholdId, items);
  }
```
`shopping_provider.dart`(同构)：
```dart
  Future<void> _save(List<ShoppingItem> items) async {
    await _repo.saveItems(activeHouseholdId, items);
  }
```
`custom_recipe_provider.dart`(方法名 `saveRecipes`)：
```dart
  Future<void> _save(List<Recipe> recipes) async {
    await _repo.saveRecipes(activeHouseholdId, recipes);
  }
```
同时把这三个 Notifier 的 `build()` 里 `_repo.loadAll()` 保持不变(读 seed)。

- [ ] **Step 5: 运行通过(需 Task 8 的 appDatabaseProvider)**

先做 Task 8 再回跑：`cd apps/mobile && flutter test test/providers/inventory_scope_save_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/sync/sync_enqueue.dart apps/mobile/lib/providers/inventory_provider.dart apps/mobile/lib/providers/shopping_provider.dart apps/mobile/lib/providers/custom_recipe_provider.dart apps/mobile/test/providers/inventory_scope_save_test.dart
git commit -m "feat(providers): persist mutations under active household scope"
```

---

## Task 8: DI 接缝 + main.dart 异步初始化 + 作用域预读

**Files:**
- Modify: `apps/mobile/lib/providers/storage_service_provider.dart`
- Modify: `apps/mobile/lib/main.dart`
- Test: `apps/mobile/test/providers/storage_provider_seam_test.dart`

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/providers/storage_provider_seam_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

void main() {
  test('repos resolve from injected AppDatabase', () {
    final db = AppDatabase(NativeDatabase.memory());
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(c.dispose);
    addTearDown(db.close);
    expect(c.read(inventoryRepoProvider), isNotNull);
    expect(c.read(shoppingRepoProvider), isNotNull);
    expect(c.read(customRecipeRepoProvider), isNotNull);
    expect(c.read(syncOutboxRepoProvider), isNotNull);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/providers/storage_provider_seam_test.dart`
Expected: 失败 — `appDatabaseProvider` 未定义。

- [ ] **Step 3: 改 storage_service_provider.dart**

- 新增 `appDatabaseProvider`(throw-by-default，main 覆盖)：
```dart
import '../storage/drift/app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider must be overridden with an AppDatabase in main().',
  );
});
```
- repo provider 改为依赖 `appDatabaseProvider`：
```dart
final inventoryRepoProvider = Provider<InventoryRepo>((ref) {
  final repo = InventoryRepo(ref.read(appDatabaseProvider));
  final seed = ref.read(inventorySeedProvider);
  if (seed != null) repo.hydrate(seed);
  return repo;
});

final shoppingRepoProvider = Provider<ShoppingRepo>((ref) {
  final repo = ShoppingRepo(ref.read(appDatabaseProvider));
  final seed = ref.read(shoppingSeedProvider);
  if (seed != null) repo.hydrate(seed);
  return repo;
});

final customRecipeRepoProvider = Provider<CustomRecipeRepo>((ref) {
  return CustomRecipeRepo(ref.read(appDatabaseProvider));
});

final syncOutboxRepoProvider = Provider<SyncOutboxRepo>((ref) {
  return SyncOutboxRepo(ref.read(appDatabaseProvider));
});
```
- `storageAdapterProvider` 与 `sharedPreferencesProvider` **保留**(settings/缓存仍用)。`AiSettingsRepo` 仍走 `storageAdapterProvider`，不动。
- 新增可选种子 provider(给 recipe seed)：
```dart
final customRecipeSeedProvider = Provider<List<Recipe>?>((ref) => null);
```
(顶部 import `../models/recipe.dart`，并在 `customRecipeRepoProvider` 内 hydrate；与 inventory/shopping 同构。)

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/providers/storage_provider_seam_test.dart`
Expected: PASS。

- [ ] **Step 5: 改 main.dart 异步初始化 + 作用域预读 + 注入**

`_runFreshPantry()` 中替换 repo 构造/注入段：
```dart
  // Drift 数据库
  final db = AppDatabase();

  // 一次性 prefs → Drift 迁移(Task 9 提供实现)；幂等。
  await migratePrefsBlobsToDrift(prefs: prefs, db: db);

  // local-only('') 作用域预读，保持 Notifier.build() 同步契约。
  final inventoryRepo = InventoryRepo(db);
  final shoppingRepo = ShoppingRepo(db);
  final customRecipeRepo = CustomRecipeRepo(db);
  final outboxRepo = SyncOutboxRepo(db);

  inventoryRepo.hydrate(await inventoryRepo.loadAllFor(''));
  await inventoryRepo.hydrateHistory();
  shoppingRepo.hydrate(await shoppingRepo.loadAllFor(''));
  customRecipeRepo.hydrate(await customRecipeRepo.loadAllFor(''));
  await outboxRepo.hydratePending();
```
`ProviderScope.overrides` 中：
```dart
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageAdapterProvider.overrideWithValue(adapter),
          inventoryRepoProvider.overrideWithValue(inventoryRepo),
          shoppingRepoProvider.overrideWithValue(shoppingRepo),
          customRecipeRepoProvider.overrideWithValue(customRecipeRepo),
          syncOutboxRepoProvider.overrideWithValue(outboxRepo),
```
顶部 import：`storage/drift/app_database.dart`、`storage/blob_to_drift_migration.dart`、`sync/sync_outbox_repo.dart`。删除不再需要的旧 repo 直 `new`(已由上面替换)。

> 说明：active household 在 `AuthGateScreen` 解析后由 `HouseholdContentSync` 通过 `replaceFromRemote` 设置 state(无需在 main 预读 household 作用域)。冷启动先显示 local-only('') 的行，与今日一致。

- [ ] **Step 6: 回跑 Task 7 的测试 + 全量分析**

Run: `cd apps/mobile && flutter test test/providers/inventory_scope_save_test.dart && flutter analyze lib/`
Expected: PASS；analyze 无 error(允许既有 warning)。

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/providers/storage_service_provider.dart apps/mobile/lib/main.dart apps/mobile/test/providers/storage_provider_seam_test.dart
git commit -m "feat(storage): wire AppDatabase DI + async hydrate in main"
```

---

## Task 9: 一次性 prefs → Drift 迁移 (幂等)

**Files:**
- Create: `apps/mobile/lib/storage/blob_to_drift_migration.dart`
- Test: `apps/mobile/test/storage/blob_to_drift_migration_test.dart`

> 老用户的 4 个 blob(+`add_history`) 导入 Drift；用 prefs 标记 `drift_migrated_v1` 保证幂等；**保留** blob 一个版本以便回滚。local-only blob 进 `householdId=''` 作用域。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/blob_to_drift_migration_test.dart`:
```dart
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/blob_to_drift_migration.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          {'id': 'a', 'name': '牛奶', 'quantity': '1', 'unit': '盒',
           'imageUrl': '', 'freshnessPercent': 1.0, 'state': 'fresh'}
        ]),
        'sync_outbox_v1': jsonEncode([
          {'id': 'op1', 'householdId': 'h1', 'entityType': 'inventoryItem',
           'entityId': 'a', 'operation': 'create', 'patch': {},
           'clientId': 'c', 'createdAt': '2026-01-01T00:00:00.000Z'}
        ]),
      }));

  test('imports blobs once; idempotent on second run', () async {
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    final repo = InventoryRepo(db);
    expect((await repo.loadAllFor('')).map((e) => e.name), ['牛奶']);
    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox.length, 1);

    // 二次运行不重复导入
    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    expect((await repo.loadAllFor('')).length, 1);
    expect((await db.select(db.syncOutbox).get()).length, 1);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/blob_to_drift_migration_test.dart`
Expected: 失败 — `migratePrefsBlobsToDrift` 未定义。

- [ ] **Step 3: 实现迁移**

Create `apps/mobile/lib/storage/blob_to_drift_migration.dart`:
```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../sync/sync_operation.dart';
import 'custom_recipe_repo.dart';
import 'drift/app_database.dart';
import 'inventory_repo.dart';
import 'shopping_repo.dart';
import '../sync/sync_outbox_repo.dart';

const _migratedFlag = 'drift_migrated_v1';

/// One-time import of legacy SharedPreferences blobs into Drift. Idempotent via
/// [_migratedFlag]; legacy blobs are left in place for one release as rollback.
Future<void> migratePrefsBlobsToDrift({
  required SharedPreferences prefs,
  required AppDatabase db,
}) async {
  if (prefs.getBool(_migratedFlag) == true) return;

  final inventory = _decodeList(prefs.getString('inventory_items'))
      .map((e) => Ingredient.fromJson(e))
      .toList();
  final shopping = _decodeList(prefs.getString('shopping_items'))
      .map((e) => ShoppingItem.fromJson(e))
      .toList();
  final recipes = _decodeList(prefs.getString('custom_recipes'))
      .map((e) => Recipe.fromJson(e))
      .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
      .toList();
  final ops = _decodeList(prefs.getString('sync_outbox_v1'))
      .map((e) => SyncOperation.fromJson(e))
      .toList();
  final history = _decodeMap(prefs.getString('add_history'));

  // local-only 作用域 ''(与冷启动种子一致)。
  await InventoryRepo(db).saveItems('', inventory);
  await ShoppingRepo(db).saveItems('', shopping);
  await CustomRecipeRepo(db).saveRecipes('', recipes);
  await SyncOutboxRepo(db).replaceAll(ops);
  if (history.isNotEmpty) await InventoryRepo(db).saveHistory(history);

  await prefs.setBool(_migratedFlag, true);
}

List<Map<String, dynamic>> _decodeList(String? raw) {
  if (raw == null) return const [];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return const [];
  }
}

Map<String, dynamic> _decodeMap(String? raw) {
  if (raw == null) return const {};
  try {
    final decoded = json.decode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/storage/blob_to_drift_migration_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/storage/blob_to_drift_migration.dart apps/mobile/test/storage/blob_to_drift_migration_test.dart
git commit -m "feat(storage): one-time idempotent prefs->drift data migration"
```

---

## Task 10: SyncCoordinator 退避重试

**Files:**
- Create: `apps/mobile/lib/sync/sync_retry_policy.dart`
- Modify: `apps/mobile/lib/sync/sync_coordinator.dart`
- Test: `apps/mobile/test/sync/sync_coordinator_retry_test.dart`

> 现 `_pushPending` 失败即抛、协调器停。改为：瞬时错误(网络/超时/`SocketException`/Supabase 5xx)按有上限指数退避重试;永久错误不重试，剩余 op 留 outbox 等下次触发。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/sync/sync_coordinator_retry_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_retry_policy.dart';

class _FlakyGateway implements RemoteSyncGateway {
  _FlakyGateway(this.failuresBeforeSuccess);
  int failuresBeforeSuccess;
  int calls = 0;
  @override
  Future<Set<String>> pushOperations(List<SyncOperation> ops) async {
    calls++;
    if (failuresBeforeSuccess-- > 0) {
      throw const SocketException('offline');
    }
    return ops.map((o) => o.id).toSet();
  }
}

// 最小 outbox stub（替代 Drift，专注测重试）
class _StubOutbox implements OutboxReader {
  _StubOutbox(this._ops);
  List<SyncOperation> _ops;
  @override
  List<SyncOperation> loadPending() => _ops;
  @override
  Future<void> removeAcknowledged(Set<String> ids) async {
    _ops = _ops.where((o) => !ids.contains(o.id)).toList();
  }
}

SyncOperation _op(String id) => SyncOperation(
      id: id, householdId: 'h1', entityType: SyncEntityType.inventoryItem,
      entityId: 'a', operation: SyncOperationType.create, patch: const {},
      clientId: 'c', createdAt: DateTime.utc(2026, 1, 1));

void main() {
  test('retries transient errors then succeeds, drains outbox', () async {
    final gw = _FlakyGateway(2);
    final outbox = _StubOutbox([_op('op1')]);
    final coord = SyncCoordinator(
      outbox: outbox,
      remote: gw,
      retry: const SyncRetryPolicy(maxAttempts: 5, baseDelay: Duration.zero),
    );
    await coord.pushPending();
    expect(gw.calls, 3); // 2 fail + 1 success
    expect(outbox.loadPending(), isEmpty);
  });

  test('gives up after maxAttempts, leaves ops in outbox', () async {
    final gw = _FlakyGateway(99);
    final outbox = _StubOutbox([_op('op1')]);
    final coord = SyncCoordinator(
      outbox: outbox,
      remote: gw,
      retry: const SyncRetryPolicy(maxAttempts: 3, baseDelay: Duration.zero),
    );
    await coord.pushPending();
    expect(gw.calls, 3);
    expect(outbox.loadPending().map((o) => o.id), ['op1']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/sync/sync_coordinator_retry_test.dart`
Expected: 失败 — `SyncRetryPolicy`/`OutboxReader`/`SyncCoordinator(retry:)` 未定义。

- [ ] **Step 3: 实现重试策略**

Create `apps/mobile/lib/sync/sync_retry_policy.dart`:
```dart
import 'dart:async';
import 'dart:io';

class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayFor(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << (attempt - 1));
    return Duration(milliseconds: ms.clamp(0, maxDelay.inMilliseconds));
  }
}

/// Transient = worth retrying (network/timeout). Everything else is permanent
/// (validation / auth) — retrying would just spin.
bool isTransientSyncError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('connection') ||
      text.contains('network');
}
```

- [ ] **Step 4: 改 SyncCoordinator**

`apps/mobile/lib/sync/sync_coordinator.dart`：
- 顶部 `import 'sync_retry_policy.dart';`
- 新增 outbox 读接口(让协调器可单测，不绑死 Drift)：
```dart
abstract class OutboxReader {
  List<SyncOperation> loadPending();
  Future<void> removeAcknowledged(Set<String> operationIds);
}
```
- `SyncOutboxRepo` 已实现这两个方法签名，让其 `implements OutboxReader`(在 `sync_outbox_repo.dart` 类声明加 `implements OutboxReader`，并 `import 'sync_coordinator.dart';`)。
- 构造与字段：
```dart
  SyncCoordinator({
    required OutboxReader outbox,
    required RemoteSyncGateway remote,
    this.retry = const SyncRetryPolicy(),
  })  : _outbox = outbox,
        _remote = remote;

  final OutboxReader _outbox;
  final RemoteSyncGateway _remote;
  final SyncRetryPolicy retry;
```
- `_pushPending` 改为带退避：
```dart
  Future<void> _pushPending() async {
    final pending = _outbox.loadPending();
    if (pending.isEmpty) return;

    for (var attempt = 1; attempt <= retry.maxAttempts; attempt++) {
      try {
        final acknowledged = await _remote.pushOperations(pending);
        await _outbox.removeAcknowledged(acknowledged);
        return;
      } catch (error) {
        final lastAttempt = attempt == retry.maxAttempts;
        if (lastAttempt || !isTransientSyncError(error)) {
          // 永久错误或重试用尽：留在 outbox，等下次触发(连网/前台/后台)。
          return;
        }
        await Future<void>.delayed(retry.delayFor(attempt));
      }
    }
  }
```
> `syncCoordinatorProvider`(`sync_providers.dart`) 现传 `SyncOutboxRepo`，类型已是 `OutboxReader`，无需改。

- [ ] **Step 5: 运行通过**

Run: `cd apps/mobile && flutter test test/sync/sync_coordinator_retry_test.dart`
Expected: 2 测试 PASS。

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/sync/sync_retry_policy.dart apps/mobile/lib/sync/sync_coordinator.dart apps/mobile/lib/sync/sync_outbox_repo.dart apps/mobile/test/sync/sync_coordinator_retry_test.dart
git commit -m "feat(sync): bounded exponential backoff for transient push errors"
```

---

## Task 11: connectivity provider + flush 协调器

**Files:**
- Create: `apps/mobile/lib/providers/connectivity_provider.dart`
- Create: `apps/mobile/lib/sync/sync_flush_coordinator.dart`
- Modify: `apps/mobile/lib/app.dart`(挂载)
- Test: `apps/mobile/test/sync/sync_flush_coordinator_test.dart`

- [ ] **Step 1: connectivity provider**

Create `apps/mobile/lib/providers/connectivity_provider.dart`:
```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` when at least one network transport is available. Overridable
/// in tests with a controlled stream.
final connectivityOnlineProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
});
```

- [ ] **Step 2: 写失败测试**

Create `apps/mobile/test/sync/sync_flush_coordinator_test.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/providers/connectivity_provider.dart';
import 'package:fresh_pantry/sync/sync_flush_coordinator.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  testWidgets('regaining connectivity triggers a flush', (tester) async {
    final online = StreamController<bool>.broadcast();
    var flushes = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectivityOnlineProvider.overrideWith((ref) => online.stream),
        syncPushPendingProvider.overrideWithValue(() async => flushes++),
      ],
      child: const MaterialApp(
        home: SyncFlushCoordinator(child: SizedBox.shrink()),
      ),
    ));
    online.add(false);
    await tester.pump();
    online.add(true); // offline -> online
    await tester.pump();
    expect(flushes, greaterThanOrEqualTo(1));
    await online.close();
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd apps/mobile && flutter test test/sync/sync_flush_coordinator_test.dart`
Expected: 失败 — `SyncFlushCoordinator` 未定义。

- [ ] **Step 4: 实现 flush 协调器**

Create `apps/mobile/lib/sync/sync_flush_coordinator.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import 'sync_providers.dart';

/// Flushes the sync outbox when the device regains connectivity or the app
/// returns to the foreground — closing the offline-edit → reconnect gap that the
/// previous "push only on next mutation" design left open.
class SyncFlushCoordinator extends ConsumerStatefulWidget {
  const SyncFlushCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncFlushCoordinator> createState() =>
      _SyncFlushCoordinatorState();
}

class _SyncFlushCoordinatorState extends ConsumerState<SyncFlushCoordinator>
    with WidgetsBindingObserver {
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }

  void _flush() {
    // unawaited: 触发即可，内部已合并并发 + 退避。
    ref.read(syncPushPendingProvider)();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectivityOnlineProvider, (prev, next) {
      final online = next.value ?? _wasOnline;
      if (online && !_wasOnline) _flush(); // offline -> online edge
      _wasOnline = online;
    });
    return widget.child;
  }
}
```

- [ ] **Step 5: 运行通过**

Run: `cd apps/mobile && flutter test test/sync/sync_flush_coordinator_test.dart`
Expected: PASS。

- [ ] **Step 6: 挂载到 app.dart**

`apps/mobile/lib/app.dart` 的 `AppShell.build`：把 `HouseholdContentSync(child: SafeArea(...))` 外再包一层(顶部 `import 'sync/sync_flush_coordinator.dart';`)：
```dart
    final pages = SyncFlushCoordinator(
      child: HouseholdContentSync(
        child: SafeArea(
          top: !isHome,
          bottom: false,
          child: IndexedStack(index: currentIndex, children: _screens),
        ),
      ),
    );
```

- [ ] **Step 7: 分析 + commit**

Run: `cd apps/mobile && flutter analyze lib/sync/ lib/providers/connectivity_provider.dart lib/app.dart`
Expected: 无 error。
```bash
git add apps/mobile/lib/providers/connectivity_provider.dart apps/mobile/lib/sync/sync_flush_coordinator.dart apps/mobile/lib/app.dart apps/mobile/test/sync/sync_flush_coordinator_test.dart
git commit -m "feat(sync): flush outbox on reconnect and app resume"
```

---

## Task 12: 同步状态 provider + 提示条

**Files:**
- Create: `apps/mobile/lib/providers/sync_status_provider.dart`
- Create: `apps/mobile/lib/widgets/common/sync_status_banner.dart`
- Modify: `apps/mobile/lib/app.dart`(在 Scaffold body 顶部叠加)
- Test: `apps/mobile/test/providers/sync_status_provider_test.dart`

> pendingCount 用 Drift `watch()` outbox 实时计数。

- [ ] **Step 1: outbox 计数流(repo 增方法)**

`apps/mobile/lib/sync/sync_outbox_repo.dart` 增：
```dart
  Stream<int> watchPendingCount() {
    final q = _db.selectOnly(_db.syncOutbox)
      ..addColumns([_db.syncOutbox.id.count()]);
    return q.map((row) => row.read(_db.syncOutbox.id.count()) ?? 0).watchSingle();
  }
```

- [ ] **Step 2: 写失败测试**

Create `apps/mobile/test/providers/sync_status_provider_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/providers/connectivity_provider.dart';
import 'package:fresh_pantry/providers/sync_status_provider.dart';

void main() {
  test('combines connectivity + pending count', () async {
    final online = StreamController<bool>.broadcast();
    final pending = StreamController<int>.broadcast();
    final c = ProviderContainer(overrides: [
      connectivityOnlineProvider.overrideWith((ref) => online.stream),
      pendingSyncCountProvider.overrideWith((ref) => pending.stream),
    ]);
    addTearDown(c.dispose);

    online.add(false);
    pending.add(3);
    await Future<void>.delayed(Duration.zero);
    final status = c.read(syncStatusProvider);
    expect(status.online, isFalse);
    expect(status.pendingCount, 3);
    expect(status.showBanner, isTrue);
    await online.close();
    await pending.close();
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd apps/mobile && flutter test test/providers/sync_status_provider_test.dart`
Expected: 失败 — providers 未定义。

- [ ] **Step 4: 实现 provider**

Create `apps/mobile/lib/providers/sync_status_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_providers.dart';
import 'connectivity_provider.dart';

final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.read(syncOutboxRepoProvider).watchPendingCount();
});

class SyncStatus {
  const SyncStatus({required this.online, required this.pendingCount});
  final bool online;
  final int pendingCount;
  bool get showBanner => !online || pendingCount > 0;
}

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final online = ref.watch(connectivityOnlineProvider).value ?? true;
  final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
  return SyncStatus(online: online, pendingCount: pending);
});
```

- [ ] **Step 5: 运行通过**

Run: `cd apps/mobile && flutter test test/providers/sync_status_provider_test.dart`
Expected: PASS。

- [ ] **Step 6: 提示条 widget + 挂载**

Create `apps/mobile/lib/widgets/common/sync_status_banner.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync_status_provider.dart';
import '../../theme/app_colors.dart';

class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    if (!status.showBanner) return const SizedBox.shrink();
    final label = status.online
        ? '同步中 · ${status.pendingCount} 条待同步'
        : status.pendingCount > 0
            ? '离线 · ${status.pendingCount} 条待同步'
            : '离线';
    return Material(
      color: status.online ? AppColors.primary : Colors.grey.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(status.online ? Icons.sync : Icons.cloud_off,
                  size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```
`app.dart` 的 `Stack` 顶部叠加(在 search overlay 之前)：
```dart
              const Positioned(
                top: 0, left: 0, right: 0,
                child: SyncStatusBanner(),
              ),
```
(顶部 `import 'widgets/common/sync_status_banner.dart';`。注意首页已有不透明状态栏 scrim，banner 叠在其上层显示。)

- [ ] **Step 7: 分析 + commit**

Run: `cd apps/mobile && flutter analyze lib/providers/sync_status_provider.dart lib/widgets/common/sync_status_banner.dart lib/sync/sync_outbox_repo.dart lib/app.dart`
Expected: 无 error。
```bash
git add apps/mobile/lib/providers/sync_status_provider.dart apps/mobile/lib/widgets/common/sync_status_banner.dart apps/mobile/lib/sync/sync_outbox_repo.dart apps/mobile/lib/app.dart apps/mobile/test/providers/sync_status_provider_test.dart
git commit -m "feat(ui): offline / pending-sync status banner"
```

---

## Task 13: 增量写入 + 响应式读 (Phase 6) — 退役全量 replace

> **❌ SKIPPED（2026-05-31，有意不做）。** 本 Task 曾实现（`2de04ee`）后回滚（`64fadf5`）。回滚根因：`add()` 改 `upsert(household, itemToAdd)`，而 `upsert` 事务内执行 `DELETE WHERE household_id=H AND id=item.id`；在 **local-only（无 household）** 场景 `syncIdFor` 不分配 uuid，`itemToAdd.id` 保持空串，于是 `DELETE ... id=''` 命中作用域内**所有空 id 行**（local-only 行 id 普遍为空，见 surrogate PK 设计），把既有物品全部删光，只留新增一条——**local-only 数据丢失**。
> 决策：正式放弃。该数据规模下（家庭库存通常几十条）全量 `saveItems`（事务内 delete-all + batch insert）本就是毫秒级，增量收益不抵 local-only 空 id 语义的复杂度与已验证的数据丢失风险（YAGNI）。若未来要做，须按 `rowPk` 而非 `id` 增量，或仅在已加入 household（id 为非空 uuid）时启用。

**Files:**
- Modify: `apps/mobile/lib/storage/inventory_repo.dart`、`shopping_repo.dart`、`custom_recipe_repo.dart`(增 `upsert`/`softDelete`/`watchAllFor`)
- Modify: `apps/mobile/lib/providers/inventory_provider.dart`(热路径 `add/remove/update` 改增量)
- Test: `apps/mobile/test/storage/inventory_repo_incremental_test.dart`

> 兑现 Drift 增量价值：单条改动不再 `delete-all + insert-all`。本 Task 仅迁移 inventory 的 `add/remove/update` 三个高频路径作为范式；shopping/recipe 与 inventory 的批量 apply 暂保持 `saveItems`(已正确、原子)。`replaceFromRemote` 仍用 `saveItems`(整 household 替换语义本就需要)。

- [ ] **Step 1: 写失败测试**

Create `apps/mobile/test/storage/inventory_repo_incremental_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

Ingredient _ing(String id, String name) => Ingredient(
      id: id, name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh);

void main() {
  late AppDatabase db;
  late InventoryRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepo(db);
  });
  tearDown(() => db.close());

  test('upsert affects only the target row', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶'), _ing('b', '蛋')]);
    await repo.upsert('h1', _ing('a', '低脂牛奶'));
    final names = (await repo.loadAllFor('h1')).map((e) => e.name).toSet();
    expect(names, {'低脂牛奶', '蛋'});
  });

  test('softDelete removes row from scope', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶')]);
    await repo.softDelete('h1', 'a');
    expect(await repo.loadAllFor('h1'), isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/storage/inventory_repo_incremental_test.dart`
Expected: 失败 — `upsert`/`softDelete` 未定义。

- [ ] **Step 3: InventoryRepo 增量方法**

`inventory_repo.dart` 增：
```dart
  Future<void> upsert(String householdId, Ingredient item) {
    return _db.into(_db.inventoryItems).insertOnConflictUpdate(
          inventoryCompanionFor(householdId, item),
        );
  }

  /// 本地物理删除该 household 作用域内的一行(同步层另发软删除 op 给远端)。
  Future<void> softDelete(String householdId, String id) {
    return (_db.delete(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId) & t.id.equals(id)))
        .go();
  }

  Stream<List<Ingredient>> watchAllFor(String householdId) {
    return (_db.select(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .watch()
        .map((rows) => rows.map(ingredientFromRow).toList());
  }
```

- [ ] **Step 4: InventoryNotifier 热路径改增量**

`inventory_provider.dart`：
- `add`：把 `await _save(updated)` 换为 `await _repo.upsert(activeHouseholdId, itemToAdd)`(state 仍乐观 + 失败回滚保留)。`record(itemToAdd)` 保持。
- `update`：`await _save(updated)` → `await _repo.upsert(activeHouseholdId, updatedItem)`。
- `remove`：`await _save(updated)` → `await _repo.softDelete(activeHouseholdId, removed.id)`。
- 其余批量方法(`applyIntakeProposals`/`applyDeductionProposals`/`clearAll`/`mergeBatch`/`insertAt`)保留 `_save`(原子替换，正确)。

> 注意：保持现有「乐观 state → 持久化 → 失败回滚 → enqueueSync」结构不变，只替换中间持久化调用。

- [ ] **Step 5: 运行通过 + 回归**

Run: `cd apps/mobile && flutter test test/storage/inventory_repo_incremental_test.dart test/providers/`
Expected: 新增 PASS；inventory 既有 provider 测试不回归。

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/storage/inventory_repo.dart apps/mobile/lib/providers/inventory_provider.dart apps/mobile/test/storage/inventory_repo_incremental_test.dart
git commit -m "perf(storage): incremental upsert/softDelete for inventory hot paths"
```

---

## Task 14: WorkManager 后台同步

**Files:**
- Create: `apps/mobile/lib/sync/background_sync.dart`
- Modify: `apps/mobile/lib/main.dart`(注册任务 + 初始化)
- Modify: `android/app/src/main/AndroidManifest.xml` 等平台配置(按 workmanager README)
- Test: `apps/mobile/test/sync/background_sync_push_test.dart`

> headless 回调跑在**独立 isolate**，**不能**用 Riverpod 树。把「初始化 Supabase + 打开 Drift + 读 outbox + push」抽成纯函数 `runBackgroundSyncPush()`，app 与 headless 共用。诚实预期：**Android 可周期执行(最小约 15min)；iOS BGTaskScheduler 受系统节流、不保证**——可靠主路径仍是 Task 11 的前台/重连 flush。

- [ ] **Step 1: 写失败测试(纯 push 逻辑可测部分)**

Create `apps/mobile/test/sync/background_sync_push_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/sync/background_sync.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

class _OkGateway implements RemoteSyncGateway {
  int calls = 0;
  @override
  Future<Set<String>> pushOperations(List<SyncOperation> ops) async {
    calls++;
    return ops.map((o) => o.id).toSet();
  }
}

void main() {
  test('drainOutbox pushes and clears pending', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    await outbox.hydratePending();
    await outbox.enqueue(SyncOperation(
        id: 'op1', householdId: 'h1', entityType: SyncEntityType.inventoryItem,
        entityId: 'a', operation: SyncOperationType.create, patch: const {},
        clientId: 'c', createdAt: DateTime.utc(2026, 1, 1)));
    final gw = _OkGateway();

    await drainOutbox(outbox: outbox, remote: gw);

    expect(gw.calls, 1);
    expect(outbox.loadPending(), isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/mobile && flutter test test/sync/background_sync_push_test.dart`
Expected: 失败 — `drainOutbox`/`runBackgroundSyncPush` 未定义。

- [ ] **Step 3: 实现 background_sync.dart**

Create `apps/mobile/lib/sync/background_sync.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../config/backend_config.dart';
import '../storage/drift/app_database.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';
import 'sync_outbox_repo.dart';

const backgroundSyncTask = 'fresh_pantry.background_sync';

/// Testable core: push everything pending through [remote], honoring the
/// coordinator's retry policy.
Future<void> drainOutbox({
  required SyncOutboxRepo outbox,
  required RemoteSyncGateway remote,
}) async {
  await SyncCoordinator(outbox: outbox, remote: remote).pushPending();
}

/// Headless entrypoint body: stand up Supabase + Drift in this isolate, then
/// drain. Returns false on init failure so WorkManager can reschedule.
Future<bool> runBackgroundSyncPush() async {
  AppDatabase? db;
  try {
    final config = BackendConfig.fromEnvironment();
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabasePublishableKey,
    );
    db = AppDatabase();
    final outbox = SyncOutboxRepo(db);
    await outbox.hydratePending();
    if (outbox.loadPending().isEmpty) return true;
    final remote = SupabaseRemotePantryRepository(
      Supabase.instance.client,
      apiBaseUrl: config.apiBaseUrl,
    );
    await drainOutbox(outbox: outbox, remote: remote);
    return true;
  } catch (_) {
    return false;
  } finally {
    await db?.close();
  }
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != backgroundSyncTask) return true;
    return runBackgroundSyncPush();
  });
}
```

- [ ] **Step 4: 运行通过**

Run: `cd apps/mobile && flutter test test/sync/background_sync_push_test.dart`
Expected: PASS。

- [ ] **Step 5: main.dart 注册**

`_runFreshPantry()`(`runApp` 之前)加：
```dart
  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    'fresh_pantry.periodic_sync',
    backgroundSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
```
顶部 `import 'sync/background_sync.dart';` + `import 'package:workmanager/workmanager.dart';`。

- [ ] **Step 6: 平台配置**

按 `workmanager` README:
- Android: 确认 `minSdkVersion`，无需额外 service(插件自带)。`@pragma('vm:entry-point')` 已加。
- iOS: `Info.plist` 加 `BGTaskSchedulerPermittedIdentifiers` 含 `fresh_pantry.periodic_sync`；`AppDelegate` 注册按 README。**记录 iOS 不保证按时**。

- [ ] **Step 7: 分析 + commit**

Run: `cd apps/mobile && flutter analyze lib/sync/background_sync.dart lib/main.dart`
Expected: 无 error。
```bash
git add apps/mobile/lib/sync/background_sync.dart apps/mobile/lib/main.dart apps/mobile/test/sync/background_sync_push_test.dart android/ ios/
git commit -m "feat(sync): WorkManager periodic background outbox drain"
```

---

## Task 15: 既有测试迁移到新 seam + 全量验证

**Files:**
- Modify: 任何用 `InMemoryStorageAdapter` 或旧 repo 构造方式注入 inventory/shopping/recipe/outbox 数据的测试。
- Test: 全量 `flutter test`

> 旧 seam(`storageAdapterProvider`/`sharedPreferencesProvider` + blob)对 inventory/shopping/recipe/outbox 已失效(它们现在走 `appDatabaseProvider`)。受影响测试改为：override `appDatabaseProvider` 为 `AppDatabase(NativeDatabase.memory())`，并用 `inventorySeedProvider`/`shoppingSeedProvider`/`customRecipeSeedProvider` 注入初始列表，或直接 `repo.saveItems('', ...)` 预置。settings 测试不受影响(仍用 prefs)。

- [ ] **Step 1: 定位受影响测试**

Run: `cd apps/mobile && grep -rln "InMemoryStorageAdapter\|inventory_items\|shopping_items\|custom_recipes\|sync_outbox_v1\|storageAdapterProvider" test/`
逐个改造(参考 Task 7/8 测试里的 override 写法)。

- [ ] **Step 2: 提供测试 helper(可选，去重)**

Create `apps/mobile/test/support/drift_test_db.dart`:
```dart
import 'package:drift/native.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());
```
在受影响测试用它 + `addTearDown(db.close)`。

- [ ] **Step 3: 全量测试**

Run: `cd apps/mobile && flutter test`
Expected: 全绿。逐个修复失败(多为 seam override 写法)。

- [ ] **Step 4: 分析 + 构建冒烟**

Run: `cd apps/mobile && flutter analyze`
Expected: 无 error。
Run: `cd apps/mobile && flutter build apk --debug`(或 `flutter build ios --debug --no-codesign`)
Expected: 构建成功。

- [ ] **Step 5: 手测冒烟清单**

- [ ] 冷启动：原 SharedPreferences 数据(若有)经迁移后完整显示。
- [ ] 增删改 → 杀进程重启 → 数据仍在(Drift 持久化)。
- [ ] 选 household → 加 item → 另一端(或重登)可见(同步未回归)。
- [ ] 飞行模式下改动 → 顶部出现「离线 · N 条待同步」→ 关飞行模式(不再手动操作)→ banner 清空，数据同步到远端(Task 11 闭环)。
- [ ] (Android) 后台放置 ~15min → outbox 被清空(Task 14)。

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/test/
git commit -m "test: migrate existing tests to drift seam; full offline-first green"
```

---

## Self-Review 结论

- **Spec 覆盖**：迁移(T1-T9) / 重连闭环(T10-T11) / 状态可视化(T12) / 增量(T13) / 后台同步(T14) / 测试迁移(T15) — 全部 Phase 0-7 有对应 Task。
- **household_id 列**：T1 加列、T3-T7 作用域读写、T9 迁移进 `''` 作用域 — 一致。
- **类型/签名一致性**：repo 统一 `loadAll()`(同步 seed)/`loadAllFor(householdId)`(异步)/`saveItems(householdId, list)`；outbox `loadPending()`(同步缓存)/`hydratePending()`；`SyncCoordinator(outbox: OutboxReader, remote, retry)`；codec 函数名在 T2 定义、T3-T6/T9 复用 — 一致。
- **无占位**：每个 code step 含真实代码与确切命令/期望。
- **已知风险**：①Drift 生成 row 类名以 `.g.dart` 为准(T2 已注明核对)；②`build()` 同步契约靠 main 预读 seed 维持(T8)；③iOS 后台不可靠(T14 已诚实标注，可靠路径是 T11)；④迁移保留 blob 一版可回滚(T9)。

## Open Risks / 后续
- 多 household 离线缓存语义已由 `household_id` 列就位；如需「离线切换 household 仍显示缓存」，让 `HouseholdContentSync`/Notifier 在 household 变化时 `loadAllFor(newId)` 作为即时种子(本计划未改该流程，保持现「切换即从远端 replace」行为)。
- shopping/recipe 的增量化(对齐 T13)与 `PersistenceQueue` 退役可作后续清理。
- 旧 blob 清理：迁移稳定一个版本后删除 `inventory_items` 等 prefs key 与回滚分支。
