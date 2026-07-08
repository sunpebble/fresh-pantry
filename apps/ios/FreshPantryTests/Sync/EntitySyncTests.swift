import Foundation
import Testing
@testable import FreshPantry

/// The generic reconciliation sequence (ADR-0004) tested once through in-memory
/// closures — no `RemotePantryRepository`, no SwiftData. Because `EntitySync.make`
/// is generic over `SyncableEntity`, this exercises the apply path all seven
/// synced entities share.
struct EntitySyncTests {
    private actor Captured {
        private(set) var saved: [Ingredient] = []
        private(set) var signals = 0
        func record(_ rows: [Ingredient]) { saved = rows }
        func signal() { signals += 1 }
    }

    private func ingredient(_ id: String, name: String = "番茄", remoteVersion: Int, deletedAt: Date? = nil) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份",
            imageUrl: "", freshnessPercent: 1, state: .fresh,
            remoteVersion: remoteVersion,
            deletedAt: deletedAt
        )
    }

    private func context(_ captured: Captured, current: Bool = true) -> SyncApplyContext {
        SyncApplyContext(
            householdId: "home",
            isCurrent: { current },
            loadPending: { [] },
            signalMerge: { await captured.signal() }
        )
    }

    private func plan(local: [Ingredient], captured: Captured) -> EntitySync {
        EntitySync.make(
            .inventoryItem,
            load: { _ in local },
            mutate: { _, transform in await captured.record(transform(local)) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in [] },
            resolveCollided: { _, _, _ in [] },
            watch: { _ in AsyncStream { $0.finish() } }
        )
    }

    @Test func applyFullMergesRemoteOverLocalOnlyThenSavesAndPulses() async {
        let captured = Captured()
        let local = [
            ingredient("local-1", name: "本地葱", remoteVersion: 0), // local-only → survives
            ingredient("synced-1", name: "已同步", remoteVersion: 4), // synced → dropped (remote is truth)
        ]
        let remoteRows = [DomainJSON.valueMap(ingredient("remote-1", name: "远端番茄", remoteVersion: 3))!]

        let applied = await plan(local: local, captured: captured).applyFull(remoteRows, context(captured))

        #expect(applied)
        #expect(await captured.saved.map(\.id) == ["remote-1", "local-1"])
        #expect(await captured.signals == 1)
    }

    @Test func applyFullBailsWhenGenerationIsStale() async {
        let captured = Captured()
        let local = [ingredient("local-1", remoteVersion: 0)]

        let applied = await plan(local: local, captured: captured).applyFull([], context(captured, current: false))

        #expect(!applied) // stale run must not let the coordinator advance the cursor
        #expect(await captured.saved.isEmpty) // stale generation → no save
        #expect(await captured.signals == 0)
    }

    @Test func applyReportsSaveFailureSoCursorHoldsBack() async {
        struct SaveError: Error {}
        let captured = Captured()
        let failing = EntitySync.make(
            SyncEntityType.inventoryItem,
            load: { _ in [Ingredient]() },
            mutate: { _, _ in throw SaveError() },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in [] },
            resolveCollided: { _, _, _ in [] },
            watch: { _ in AsyncStream { $0.finish() } }
        )
        let rows = [DomainJSON.valueMap(ingredient("remote-1", remoteVersion: 3))!]

        #expect(await failing.applyFull(rows, context(captured)) == false)
        #expect(await failing.applyPatch(rows, context(captured)) == false)
        #expect(await captured.signals == 0) // failed save → no merge pulse

        // An empty (but current) delta is a successful no-op — it must not
        // hold the cursor back.
        #expect(await failing.applyPatch([], context(captured)) == true)
    }

    // MARK: uploadLocalOnly PK-collision routing

    /// Records `resolveCollided` invocations so tests can assert routing.
    private actor CollisionRecorder {
        private(set) var calls: [(entityType: SyncEntityType, hid: String, rows: [[String: JSONValue]])] = []
        func record(_ entityType: SyncEntityType, _ hid: String, _ rows: [[String: JSONValue]]) {
            calls.append((entityType, hid, rows))
        }
    }

    /// A canonical-UUID id — the only kind whose bulk upsert ships an `id`
    /// column and can therefore collide on the primary key.
    private let uuidId = "33333333-3333-3333-3333-333333333333"

    private func uploadPlan(
        local: [Ingredient],
        captured: Captured,
        recorder: CollisionRecorder,
        inserted: Set<String>,
        resolved: Set<String>
    ) -> EntitySync {
        EntitySync.make(
            .inventoryItem,
            load: { _ in local },
            mutate: { _, transform in await captured.record(transform(local)) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in inserted },
            resolveCollided: { entityType, hid, rows in
                await recorder.record(entityType, hid, rows)
                return resolved
            },
            watch: { _ in AsyncStream { $0.finish() } }
        )
    }

    private var uploadScope: LocalUploadScope { LocalUploadScope(householdID: "home", pendingOps: []) }

    @Test func uploadDoesNotFakeBumpCollidedRowWhenResolutionFails() async throws {
        // The bulk upsert inserted NOTHING: the UUID row was DO-NOTHING'd
        // against an existing remote row (e.g. a tombstone), the non-UUID row
        // never ships an id column (fresh remote id — its absence from the
        // inserted set is normal). Unresolved collided rows must stay at
        // remoteVersion 0 — the old blanket v1 bump made the next full pull
        // silently drop them.
        let captured = Captured()
        let recorder = CollisionRecorder()
        let local = [
            ingredient(uuidId, name: "撞墓碑", remoteVersion: 0),
            ingredient("local-1", name: "本地葱", remoteVersion: 0),
        ]
        let sync = uploadPlan(local: local, captured: captured, recorder: recorder, inserted: [], resolved: [])

        try await sync.uploadLocalOnly(uploadScope, context(captured))

        let saved = await captured.saved
        #expect(saved.first { $0.id == uuidId }?.remoteVersion == 0)
        #expect(saved.first { $0.id == "local-1" }?.remoteVersion == 1)
    }

    @Test func uploadRoutesCollidedRowsThroughResolutionAndBumpsResolved() async throws {
        let captured = Captured()
        let recorder = CollisionRecorder()
        let local = [ingredient(uuidId, name: "撞墓碑", remoteVersion: 0)]
        let sync = uploadPlan(
            local: local, captured: captured, recorder: recorder,
            inserted: [], resolved: [uuidId]
        )

        try await sync.uploadLocalOnly(uploadScope, context(captured))

        let calls = await recorder.calls
        try #require(calls.count == 1)
        #expect(calls[0].entityType == .inventoryItem)
        #expect(calls[0].hid == "home")
        try #require(calls[0].rows.count == 1)
        #expect(calls[0].rows[0]["id"] == .string(uuidId))
        // Resolution succeeded (tombstone revived / live row confirmed) → the
        // v1 bump is now truthful.
        #expect(await captured.saved.first { $0.id == uuidId }?.remoteVersion == 1)
    }

    @Test func uploadBumpDerivesFromFreshLocalSnapshotNotTheUploadOne() async throws {
        // Local writes landing while the upload's network round-trips are in
        // flight must survive the bump save: deriving `bumped` from the stale
        // pre-upload snapshot would silently revert the edit and drop the new
        // row. The bump's mutate transforms the repository's CURRENT rows
        // (`fresh`), never the upload-phase snapshot.
        let captured = Captured()
        let uploadSnapshot = [ingredient(uuidId, name: "旧名", remoteVersion: 0)]
        let fresh = [
            ingredient(uuidId, name: "编辑后", remoteVersion: 0),
            ingredient("added-1", name: "窗口期新增", remoteVersion: 0),
        ]
        let sync = EntitySync.make(
            .inventoryItem,
            load: { _ in uploadSnapshot },
            mutate: { _, transform in await captured.record(transform(fresh)) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in [self.uuidId] },
            resolveCollided: { _, _, _ in [] },
            watch: { _ in AsyncStream { $0.finish() } }
        )

        try await sync.uploadLocalOnly(uploadScope, context(captured))

        let saved = await captured.saved
        let bumpedRow = saved.first { $0.id == uuidId }
        #expect(bumpedRow?.remoteVersion == 1)
        #expect(bumpedRow?.name == "编辑后")  // the mid-window edit survives
        #expect(saved.first { $0.id == "added-1" }?.remoteVersion == 0)  // untouched
    }

    // MARK: load→save 窗口竞态(并发本地写不得被全量替换回退)

    /// 有状态的内存仓库:load/save 都经同一个 actor,模拟真实 `@ModelActor`
    /// 仓库 —— 两次独立调用之间可以插入并发写。
    private actor FakeRepo {
        private(set) var rows: [Ingredient]
        init(_ rows: [Ingredient]) { self.rows = rows }
        func load() -> [Ingredient] { rows }
        func mutate(_ transform: @Sendable ([Ingredient]) -> [Ingredient]) { rows = transform(rows) }
        func insert(_ row: Ingredient) { rows.append(row) }
    }

    private actor Counter {
        private var n = 0
        func next() -> Int { n += 1; return n }
    }

    private func plan(repo: FakeRepo) -> EntitySync {
        EntitySync.make(
            .inventoryItem,
            // 哨兵:applyFull/applyPatch 的一切本地读写都必须在原子 mutate 内。
            // 若实现回归为「独立 load + save」两段式(哪怕守卫全部前置、当前
            // 断言仍能碰巧通过),这里结构性失败。
            load: { _ in
                Issue.record("applyFull/applyPatch 不得调用独立 load —— 必须走原子 mutate")
                return []
            },
            mutate: { _, transform in await repo.mutate(transform) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in [] },
            resolveCollided: { _, _, _ in [] },
            watch: { _ in AsyncStream { $0.finish() } }
        )
    }

    /// 在 apply 的 load 之后、save 之前的挂起点(第二次 isCurrent 守卫)落盘
    /// 一笔并发用户写的上下文。
    private func contextWritingConcurrently(_ repo: FakeRepo, steps: Counter) -> SyncApplyContext {
        SyncApplyContext(
            householdId: "home",
            isCurrent: {
                if await steps.next() == 2 {
                    await repo.insert(self.ingredient("concurrent-1", name: "窗口期新增", remoteVersion: 0))
                }
                return true
            },
            loadPending: { [] },
            signalMerge: {}
        )
    }

    @Test func applyPatchDoesNotRevertAConcurrentLocalWrite() async {
        // applyPatch 的本地快照 load 与 save 之间存在挂起点:窗口内落盘的
        // 本地写若被窗口前快照的全量替换覆盖,用户已确认的操作就被静默回退。
        let repo = FakeRepo([ingredient("existing-1", name: "既有", remoteVersion: 1)])
        let sync = plan(repo: repo)
        let ctx = contextWritingConcurrently(repo, steps: Counter())
        let delta = [DomainJSON.valueMap(ingredient("remote-1", name: "远端更新", remoteVersion: 3))!]

        #expect(await sync.applyPatch(delta, ctx))

        let ids = await repo.rows.map(\.id)
        #expect(ids.contains("concurrent-1")) // 窗口期的并发写幸存
        #expect(ids.contains("remote-1")) // delta 照常落地
        #expect(ids.contains("existing-1"))
    }

    @Test func applyFullDoesNotRevertAConcurrentLocalWrite() async {
        // applyFull(realtime 快照与全量拉取共用)同一形状的窗口。
        let repo = FakeRepo([ingredient("existing-1", name: "既有", remoteVersion: 1)])
        let sync = plan(repo: repo)
        let ctx = contextWritingConcurrently(repo, steps: Counter())
        let remoteRows = [DomainJSON.valueMap(ingredient("remote-1", name: "远端", remoteVersion: 3))!]

        #expect(await sync.applyFull(remoteRows, ctx))

        let ids = await repo.rows.map(\.id)
        #expect(ids.contains("concurrent-1")) // 窗口期的并发写幸存
        #expect(ids.contains("remote-1"))
    }

    @Test func uploadDoesNotResurrectARowTombstonedDuringItsNetworkWindow() async throws {
        // 已确认的僵尸行序列:startSync 的 uploadLocalOnly 网络窗口内,
        // refreshDelta 的 applyPatch 应用了 zombie-1 的墓碑并(在 coordinator
        // 层)推进 cursor。之后的版本 bump 保存若从窗口前快照派生,会复活
        // zombie-1 —— cursor 已越过墓碑,重叠窗口之外永不再拉,僵尸行跨启动
        // 存活。bump 必须从墓碑应用后的状态派生。
        let repo = FakeRepo([
            ingredient(uuidId, name: "上传中", remoteVersion: 0),
            ingredient("zombie-1", name: "将被墓碑", remoteVersion: 1),
        ])
        let patcher = plan(repo: repo)
        let ctx = SyncApplyContext(
            householdId: "home", isCurrent: { true }, loadPending: { [] }, signalMerge: {}
        )
        let sync = EntitySync.make(
            .inventoryItem,
            load: { _ in await repo.load() },
            mutate: { _, transform in await repo.mutate(transform) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in
                // 网络窗口:并发的增量刷新应用 zombie-1 的墓碑。
                let tombstone = DomainJSON.valueMap(
                    self.ingredient("zombie-1", name: "将被墓碑", remoteVersion: 2, deletedAt: Date())
                )!
                _ = await patcher.applyPatch([tombstone], ctx)
                return [self.uuidId]
            },
            resolveCollided: { _, _, _ in [] },
            watch: { _ in AsyncStream { $0.finish() } }
        )

        try await sync.uploadLocalOnly(uploadScope, ctx)

        let rows = await repo.rows
        #expect(!rows.map(\.id).contains("zombie-1")) // 墓碑不被复活
        #expect(rows.first { $0.id == uuidId }?.remoteVersion == 1)
    }

    @Test func uploadBumpsInsertedRowsWithoutResolution() async throws {
        // A cleanly inserted UUID row is synced — no resolution round-trip.
        let captured = Captured()
        let recorder = CollisionRecorder()
        let local = [ingredient(uuidId, name: "顺利入库", remoteVersion: 0)]
        let sync = uploadPlan(
            local: local, captured: captured, recorder: recorder,
            inserted: [uuidId], resolved: []
        )

        try await sync.uploadLocalOnly(uploadScope, context(captured))

        #expect(await recorder.calls.isEmpty)
        #expect(await captured.saved.first { $0.id == uuidId }?.remoteVersion == 1)
    }
}
