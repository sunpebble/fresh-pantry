import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'backend/backend_config_provider.dart';
import 'config/backend_config.dart';
import 'config/sentry_config.dart';
import 'providers/ai_draft_provider.dart';
import 'providers/invite_link_provider.dart';
import 'providers/notification_service_provider.dart';
import 'providers/storage_service_provider.dart';
import 'services/invite_link_service.dart';
import 'services/notification_service.dart';
import 'services/share_intent_service.dart';
import 'storage/blob_to_drift_migration.dart';
import 'storage/custom_recipe_repo.dart';
import 'storage/drift/app_database.dart';
import 'storage/inventory_repo.dart';
import 'storage/shared_prefs_storage_adapter.dart';
import 'storage/shopping_repo.dart';
import 'sync/background_sync.dart';
import 'sync/sync_outbox_repo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final sentryConfig = SentryConfig.fromEnvironment();
  await SentryFlutter.init((options) {
    options.dsn = sentryConfig.dsn;
    options.tracesSampleRate = sentryConfig.tracesSampleRate;
    options.replay.sessionSampleRate = sentryConfig.replaySessionSampleRate;
    options.replay.onErrorSampleRate = sentryConfig.replayOnErrorSampleRate;
    options.privacy.maskAllText = true;
    options.privacy.maskAllImages = true;
    if (sentryConfig.environment.trim().isNotEmpty) {
      options.environment = sentryConfig.environment;
    }
  }, appRunner: _runFreshPantry);
}

Future<void> _runFreshPantry() async {
  final backendConfig = BackendConfig.fromEnvironment();
  await Supabase.initialize(
    url: backendConfig.supabaseUrl,
    anonKey: backendConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  final notificationService = NotificationService();
  await notificationService.init();
  final prefs = await SharedPreferences.getInstance();
  final adapter = SharedPrefsStorageAdapter(prefs);

  // Drift database backing structured persistence.
  final db = AppDatabase();

  // One-time, idempotent import of legacy SharedPreferences blobs into Drift.
  await migratePrefsBlobsToDrift(prefs: prefs, db: db);

  final inventoryRepo = InventoryRepo(db);
  final shoppingRepo = ShoppingRepo(db);
  final customRecipeRepo = CustomRecipeRepo(db);
  final outboxRepo = SyncOutboxRepo(db);

  // Pre-read the local-only ('') scope so the notifiers' synchronous `build()`
  // contract holds while Drift reads are async. add_history and the outbox are
  // hydrated into memory for the same reason; skipping hydrateHistory would make
  // a cold start see an empty history and truncate it on the first add.
  inventoryRepo.hydrate(await inventoryRepo.loadAllFor(''));
  await inventoryRepo.hydrateHistory();
  shoppingRepo.hydrate(await shoppingRepo.loadAllFor(''));
  customRecipeRepo.hydrate(await customRecipeRepo.loadAllFor(''));
  await outboxRepo.hydratePending();

  // Periodic background outbox drain (Android/iOS only; a no-op elsewhere). The
  // reliable sync path remains the foreground/reconnect flush — this only
  // narrows the gap when the app is killed and the user doesn't reopen it.
  await _scheduleBackgroundSync();

  runApp(
    SentryWidget(
      child: ProviderScope(
        overrides: [
          notificationServiceProvider.overrideWithValue(notificationService),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageAdapterProvider.overrideWithValue(adapter),
          inventoryRepoProvider.overrideWithValue(inventoryRepo),
          shoppingRepoProvider.overrideWithValue(shoppingRepo),
          customRecipeRepoProvider.overrideWithValue(customRecipeRepo),
          syncOutboxRepoProvider.overrideWithValue(outboxRepo),
          systemShareSourceProvider.overrideWithValue(
            createSystemShareSource(),
          ),
          inviteLinkSourceProvider.overrideWithValue(createInviteLinkSource()),
          backendConfigProvider.overrideWithValue(backendConfig),
        ],
        child: const FreshPantryApp(),
      ),
    ),
  );
}

/// Schedules the periodic background outbox drain on platforms with a
/// WorkManager backend (Android / iOS). Desktop and web have none, so this is a
/// no-op there. [ExistingWorkPolicy.keep] avoids stacking duplicate periodic
/// work across relaunches. iOS execution timing is system-throttled and not
/// guaranteed — the foreground/reconnect flush stays the dependable path.
Future<void> _scheduleBackgroundSync() async {
  final supportsWorkManager =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!supportsWorkManager) return;

  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundSyncUniqueName,
    backgroundSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
