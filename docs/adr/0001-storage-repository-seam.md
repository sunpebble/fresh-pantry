# ADR-0001: Storage Repository Seam

Date: 2026-05-22

## Status

Accepted

## Context

Every stateful notifier (`InventoryNotifier`, `ShoppingNotifier`, `CustomRecipeNotifier`, `AiSettingsNotifier`) has a hard dependency on `SharedPreferences`. This means:

- **No adapter seam**: There is no `StorageRepository` interface — notifiers call `_prefs.setString()` and `_prefs.getString()` directly. Changing the storage backend would touch every notifier file.
- **Tests are platform-coupled**: Testing provider logic requires mocking `SharedPreferences`, which is awkward, async, and tied to the Flutter SDK.
- **Mixed concerns**: JSON encoding/decoding, persistence, and domain normalization all live in the same notifier files, making it unclear where data integrity responsibility lives.
- **Seed hydration is duplicated**: `main.dart` pre-decodes seeds and injects them via separate providers (`inventorySeedProvider`, `shoppingSeedProvider`, `customRecipeSeedProvider`). Each seed provider has its own fallback that re-implements the decode path.

The deletion test: if we deleted `SharedPreferences` from every notifier, all persistence complexity would need to be recreated across N notifiers. A `StorageAdapter` would concentrate that complexity into one module.

## Decision

Introduce a **two-layer storage seam**:

### Layer 1: `StorageAdapter` (low-level, raw string persistence)

```dart
abstract class StorageAdapter {
  String? read(String key);
  Future<void> write(String key, String value);
}
```

Two adapters from day one — a real seam:
- `SharedPrefsStorageAdapter` — production, backed by `SharedPreferences`
- `InMemoryStorageAdapter` — tests, backed by a `Map<String, String>`

### Layer 2: Domain repos (one per aggregate)

Concrete classes, each taking a `StorageAdapter` in the constructor. Each repo owns:
- Its storage key(s)
- JSON serialization/deserialization
- Load-time normalization (category, freshness, deduplication)
- Optimistic fire-and-forget writes (state updates before persistence completes)

| Repo | Keys |
|------|------|
| `InventoryRepo` | `inventory_items`, `add_history` |
| `ShoppingRepo` | `shopping_items` |
| `CustomRecipeRepo` | `custom_recipes` |
| `AiSettingsRepo` | `ai_settings_v1` |

### Seed hydration

The `InventoryRepo`, `ShoppingRepo`, and `CustomRecipeRepo` each expose a `hydrate(seed)` method. `main.dart` pre-decodes the seeds (avoiding JSON on the first frame), then calls `repo.hydrate(seed)` before the app widget mounts. `loadAll()` returns the hydrated seed synchronously on first call, then reads from the adapter on subsequent calls.

### Notifier changes

Notifiers read from repos instead of `SharedPreferences`:

```dart
// Before
_prefs = ref.read(sharedPreferencesProvider);
return ref.read(inventorySeedProvider);
// ...
await _prefs.setString(_kInventoryKey, json.encode(...));

// After
_repo = ref.read(inventoryRepoProvider);
return _repo.loadAll();
// ...
_repo.saveItems(updated);
```

`PersistenceQueue` mixin stays on notifiers — it serializes writes at the notifier level and is a separate concern from storage (see future ADR for unified persistence semantics).

### Riverpod wiring

```dart
final storageAdapterProvider = Provider<StorageAdapter>((ref) {
  throw UnimplementedError('Must be overridden in main()');
});

final inventoryRepoProvider = Provider<InventoryRepo>((ref) {
  return InventoryRepo(ref.read(storageAdapterProvider));
});
```

`main.dart` overrides both with real instances.

## Consequences

**Positive:**
- Tests use `InMemoryStorageAdapter` — no `SharedPreferences` setup, no async, no platform dependency.
- Storage backend can be swapped by changing one adapter implementation.
- Data integrity responsibility is concentrated in repos — load-time normalization lives in one place.
- Seed providers are eliminated (4 files deleted, logic absorbed by repos).
- Notifiers shrink — JSON encode/decode moves to repos.

**Negative:**
- One additional indirection layer (notifier → repo → adapter) — adds ~2 lines per notifier.
- `main.dart` must know about repos for hydration (but this is already true for seed providers).

**Neutral:**
- `PersistenceQueue` remains on notifiers as a separate concern. Future ADR may move it.
- `FoodDetailsRepository` and `RecipeSearchRepository` (which use `SharedPreferences` for caching) are not changed in this ADR — their cache layer is a separate concern addressed by the search/food-details repo design.
