import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/ai_draft_provider.dart';
import 'providers/notification_service_provider.dart';
import 'providers/storage_service_provider.dart';
import 'services/notification_service.dart';
import 'services/share_intent_service.dart';
import 'storage/custom_recipe_repo.dart';
import 'storage/inventory_repo.dart';
import 'storage/shared_prefs_storage_adapter.dart';
import 'storage/shopping_repo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final notificationService = NotificationService();
  await notificationService.init();
  final prefs = await SharedPreferences.getInstance();
  final adapter = SharedPrefsStorageAdapter(prefs);

  final inventoryRepo = InventoryRepo(adapter);
  final shoppingRepo = ShoppingRepo(adapter);
  final customRecipeRepo = CustomRecipeRepo(adapter);

  // Pre-decode seeds to avoid JSON parse on the first frame.
  inventoryRepo.hydrate(inventoryRepo.loadAll());
  shoppingRepo.hydrate(shoppingRepo.loadAll());
  customRecipeRepo.hydrate(customRecipeRepo.loadAll());

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageAdapterProvider.overrideWithValue(adapter),
        inventoryRepoProvider.overrideWithValue(inventoryRepo),
        shoppingRepoProvider.overrideWithValue(shoppingRepo),
        customRecipeRepoProvider.overrideWithValue(customRecipeRepo),
        systemShareSourceProvider.overrideWithValue(createSystemShareSource()),
      ],
      child: const FreshPantryApp(),
    ),
  );
}
