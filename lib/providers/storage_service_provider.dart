import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/ai_settings_repo.dart';
import '../storage/custom_recipe_repo.dart';
import '../storage/inventory_repo.dart';
import '../storage/shared_prefs_storage_adapter.dart';
import '../storage/shopping_repo.dart';
import '../storage/storage_adapter.dart';

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
  return InventoryRepo(ref.read(storageAdapterProvider));
});

final shoppingRepoProvider = Provider<ShoppingRepo>((ref) {
  return ShoppingRepo(ref.read(storageAdapterProvider));
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
