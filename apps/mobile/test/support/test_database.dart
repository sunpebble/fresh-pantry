import 'package:drift/native.dart';
// `Override` (the ProviderScope/ProviderContainer override type) is surfaced by
// flutter_riverpod's `misc.dart`, not the main barrel, in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/connectivity_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/providers/sync_status_provider.dart';
// Scope the drift import to `AppDatabase`: the generated `app_database.g.dart`
// also declares a `ShoppingItem` data class that would otherwise collide with
// `models/shopping_item.dart`. The helper only needs `AppDatabase`.
import 'package:fresh_pantry/storage/drift/app_database.dart' show AppDatabase;
import 'package:fresh_pantry/storage/local_recipe_repository.dart';

/// A fresh in-memory Drift database for a single test.
///
/// Pair with [addTearDown]`(db.close)` so each test gets an isolated database.
AppDatabase newTestDatabase() => AppDatabase(NativeDatabase.memory());

/// Standard storage overrides for widget/provider tests.
///
/// Replaces the old `sharedPreferencesProvider`-only pattern: structured data
/// (inventory / shopping / custom recipes / sync outbox) now lives in Drift, so
/// every test that touches those notifiers must override [appDatabaseProvider]
/// with an in-memory database. Optional seeds hydrate the matching notifier on
/// its first synchronous `build()`, mirroring how `main.dart` injects the
/// pre-read snapshot in production.
List<Override> testStorageOverrides({
  required AppDatabase database,
  List<Ingredient>? inventory,
  List<ShoppingItem>? shopping,
  List<Recipe>? customRecipes,
  LocalRecipeRepository? localRecipeRepository,
}) {
  return [
    appDatabaseProvider.overrideWithValue(database),
    if (inventory != null) inventorySeedProvider.overrideWithValue(inventory),
    if (shopping != null) shoppingSeedProvider.overrideWithValue(shopping),
    if (customRecipes != null)
      customRecipeSeedProvider.overrideWithValue(customRecipes),
    ...localRecipeTestOverrides(repository: localRecipeRepository),
    ...syncBannerTestOverrides(),
  ];
}

/// Overrides that keep AppShell's SyncStatusBanner hermetic in widget tests.
///
/// The banner watches a Drift outbox query stream (whose cleanup timer trips
/// flutter_test's pending-timer check at teardown) and the connectivity plugin
/// (which has no test binding). [Stream.value] emits via a microtask, not a
/// Timer, so nothing stays pending. Folded into [testStorageOverrides]; spread
/// directly in tests that build their own override list instead of the helper.
List<Override> syncBannerTestOverrides() => [
  pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
  connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
];

/// Keeps the explore tab hermetic in widget tests. RecipesScreen and the
/// dashboard's ExpiringFallbackCard watch recipesFetchProvider, which would
/// otherwise load the real ~1MB asset via rootBundle and stall pumpAndSettle.
/// Folded into [testStorageOverrides]; spread directly in tests that build
/// their own override list. Pass [repository] to supply specific recipes.
List<Override> localRecipeTestOverrides({LocalRecipeRepository? repository}) =>
    [
      localRecipeRepositoryProvider.overrideWithValue(
        repository ?? LocalRecipeRepository(loadString: (_) async => '[]'),
      ),
    ];
