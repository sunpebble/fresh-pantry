# ADR-0004: Household sync reconciliation collapses into a generic EntityPlan

Date: 2026-06-22

## Status

Accepted

## Context

`HouseholdContentSyncCoordinator` (680 lines) was ported verbatim from the Dart
`household_content_sync_coordinator.dart`. The port never received Swift's
generic treatment, so the same local⇄remote reconciliation shape —
decode → merge → save → signal — is hand-written **21 times**: `apply` × 7
entities, `patch` × 7, and the `uploadLocalOnly` block × 7, plus `subscribe`
(7 tasks) and three list-of-7 call sites (startSync apply, startSync patch,
refreshDelta patch, cursor-advance). `HouseholdMergePolicy` mirrors this with
**14** thin type-bridge wrappers (`mergeX`/`patchX`) over a generic core, and a
`isSoftDeleted` that switches on the concrete type.

The per-entity variation across all 21 coordinator blocks is small: entity type,
the local repository, the decode/identity predicate, the merge function, and the
divergent save name (`saveItems`/`saveRecipes`/`saveEntries`). Everything else is
identical. Adding the favorite-recipe and dietary-preference entities each
required edits at 8+ sites across two files.

The deletion test: deleting the 21 blocks and replacing them with a generic
sequence **concentrates** complexity — the apply path becomes one place to read
and one place to test (it is currently untested; the coordinator appears in tests
only for the pure `shouldRetry` gate). The repeated blocks were hiding real depth,
not adding it.

Two adjacent layers have the *same* 7× shape but are **not** collapsed here:

- `RemotePantryRepository`'s per-entity `loadX`/`upsertX`/`watchX` wrappers are
  already thin over shared cores, and the wire mapping (table names, snake_case
  RPC params, column↔field encoding) is **parity-critical, byte-for-byte** with
  the Flutter client. Refactoring it risks the Supabase contract for little
  shallow-mass removed.
- The repository `save` names (`saveItems`/`saveRecipes`/`saveEntries`) have ~47
  call sites, many in feature stores. Renaming is pure cosmetic churn with no
  behaviour change.

## Decision

Introduce a `SyncableEntity` protocol the seven synced models conform to:

```swift
protocol SyncableEntity: Codable, Sendable {
    var id: String { get }
    var remoteVersion: Int { get }
    var deletedAt: Date? { get }
    var hasSyncIdentity: Bool { get }       // !name / !recipeId / !keyword / !recipeID
    func withRemoteVersion(_ v: Int) -> Self
}
```

With it:

- `HouseholdMergePolicy` becomes two generic methods (`merge<T>`, `patch<T>`);
  the 14 wrappers and the `isSoftDeleted` type-switch are deleted. Soft-delete is
  `deletedAt != nil`; the local-only / well-formed predicates derive from the
  protocol.
- A generic `plan<T: SyncableEntity>(…)` factory carries the
  decode → merge → save → signal sequence **once**, producing an `EntityPlan`
  value that binds one entity's I/O (local load/save, remote load/upsert/watch)
  via closures — so `RemotePantryRepository` and the repo `save` methods are
  reached without being modified or renamed.
- `HouseholdContentSyncCoordinator` holds `plans: [EntityPlan]` built in `init`;
  `startSync`, `refreshDelta`, `subscribe`, `uploadLocalOnly`, and cursor-advance
  **loop** over it. Adding an eighth synced entity becomes a single `plan(…)`
  line.

The refactor is **parity-exact**: `LocalUploadScope` is still rebuilt per-apply
and `signalMerge` still fires per-entity, identical to today, so the existing
suite is a tight safety net. Building the scope once per run and coalescing the
merge signal are recorded as separate follow-ups, not part of this change.

It lands in two independently-green phases: (A) `SyncableEntity` + the
`HouseholdMergePolicy` collapse under its existing tests; (B) the `EntityPlan`
factory + coordinator loop, with one focused `EntityPlan.applyFull` test.

`foodLog.migrateLegacyIds()` stays a `startSync` preamble (one-shot, foodLog-only,
outside the loop). `ShoppingRepository.mergeFromRemote` is not in any apply path
(production-dead; only a repo test calls it) and is left untouched.

## Consequences

- The apply sequence is one deep module, testable once for all seven entities.
- `HouseholdMergePolicy` shrinks from ~277 lines to ~40; the type-switch is gone.
- Leverage: add a synced entity in one line instead of ~8 edit sites.
- `RemotePantryRepository` stays byte-for-byte parity-critical and untouched.
- Future architecture reviews should **not** re-suggest collapsing
  `RemotePantryRepository`'s per-entity wrappers or renaming the repo `save`
  methods — both were considered and deliberately left. Revisit only if the wire
  contract is already being changed for another reason.
