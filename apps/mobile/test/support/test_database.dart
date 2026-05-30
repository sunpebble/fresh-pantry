import 'package:drift/native.dart';
// `Override` (the ProviderScope/ProviderContainer override type) is surfaced by
// flutter_riverpod's `misc.dart`, not the main barrel, in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
// Scope the drift import to `AppDatabase`: the generated `app_database.g.dart`
// also declares a `ShoppingItem` data class that would otherwise collide with
// `models/shopping_item.dart`. The helper only needs `AppDatabase`.
import 'package:fresh_pantry/storage/drift/app_database.dart' show AppDatabase;

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
}) {
  return [
    appDatabaseProvider.overrideWithValue(database),
    if (inventory != null) inventorySeedProvider.overrideWithValue(inventory),
    if (shopping != null) shoppingSeedProvider.overrideWithValue(shopping),
    if (customRecipes != null)
      customRecipeSeedProvider.overrideWithValue(customRecipes),
  ];
}
