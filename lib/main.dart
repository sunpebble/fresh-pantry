import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/ai_draft_provider.dart';
import 'providers/custom_recipe_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/shopping_provider.dart';
import 'providers/storage_service_provider.dart';
import 'services/share_intent_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // 启动时预解码三大持久化 blob,把 jsonDecode 移出首帧。
  // 解码失败 / 缺省由各 helper 自身的 try/catch 兜底回到 mock 或空列表。
  final inventorySeed = loadInventoryFromPrefs(prefs);
  final shoppingSeed = loadShoppingFromPrefs(prefs);
  final customRecipeSeed = loadCustomRecipesFromPrefs(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inventorySeedProvider.overrideWithValue(inventorySeed),
        shoppingSeedProvider.overrideWithValue(shoppingSeed),
        customRecipeSeedProvider.overrideWithValue(customRecipeSeed),
        systemShareSourceProvider.overrideWithValue(ReceiveSharingIntentSource()),
      ],
      child: const FreshPantryApp(),
    ),
  );
}
