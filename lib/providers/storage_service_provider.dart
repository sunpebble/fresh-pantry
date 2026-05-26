import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../storage/ai_settings_repo.dart';
import '../storage/custom_recipe_repo.dart';
import '../storage/inventory_repo.dart';
import '../storage/shared_prefs_storage_adapter.dart';
import '../storage/shopping_repo.dart';
import '../storage/storage_adapter.dart';

/// Optional startup/test seed for inventory. When overridden, the repo hydrates
/// from this list instead of reading storage on first load.
final inventorySeedProvider = Provider<List<Ingredient>?>((ref) => null);

/// Optional startup/test seed for shopping.
final shoppingSeedProvider = Provider<List<ShoppingItem>?>((ref) => null);

/// Provider for the storage adapter.
///
/// Falls back to [sharedPreferencesProvider] if not overridden — this allows
/// existing tests that only override [sharedPreferencesProvider] to keep
/// working without changes. Production code should override this directly
/// via [ProviderScope] overrides in `main()`.
final storageAdapterProvider = Provider<StorageAdapter>((ref) {
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    return SharedPrefsStorageAdapter(prefs);
  } catch (_) {
    throw UnimplementedError(
      'Either storageAdapterProvider must be overridden, '
      'or sharedPreferencesProvider must be available as fallback.',
    );
  }
});

final inventoryRepoProvider = Provider<InventoryRepo>((ref) {
  final repo = InventoryRepo(ref.read(storageAdapterProvider));
  final seed = ref.read(inventorySeedProvider);
  if (seed != null) {
    repo.hydrate(seed);
  }
  return repo;
});

final shoppingRepoProvider = Provider<ShoppingRepo>((ref) {
  final repo = ShoppingRepo(ref.read(storageAdapterProvider));
  final seed = ref.read(shoppingSeedProvider);
  if (seed != null) {
    repo.hydrate(seed);
  }
  return repo;
});

final customRecipeRepoProvider = Provider<CustomRecipeRepo>((ref) {
  return CustomRecipeRepo(ref.read(storageAdapterProvider));
});

final aiSettingsRepoProvider = Provider<AiSettingsRepo>((ref) {
  return AiSettingsRepo(ref.read(storageAdapterProvider));
});

/// Provider for SharedPreferences instance.
///
/// Throws by default — must be overridden in [ProviderScope] in `main()`.
/// Kept for food_details_provider and recipe_provider which will be
/// migrated in a future ADR.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with SharedPreferences '
    'instance via ProviderScope overrides.',
  );
});
