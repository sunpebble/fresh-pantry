import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../config/backend_config.dart';
import '../storage/drift/app_database.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';
import 'sync_outbox_repo.dart';

/// WorkManager task name handed to the callback dispatcher.
const backgroundSyncTask = 'fresh_pantry.background_sync';

/// Unique WorkManager work id for the periodic registration. Reusing it with a
/// keep policy means re-launches don't stack duplicate periodic work.
const backgroundSyncUniqueName = 'fresh_pantry.periodic_sync';

/// Testable core: drain everything pending in [outbox] through [remote],
/// reusing the coordinator's coalescing + bounded-retry policy.
///
/// No Riverpod, no platform channels — safe to call from the headless
/// background isolate as well as from a unit test.
Future<void> drainOutbox({
  required OutboxReader outbox,
  required RemoteSyncGateway remote,
}) {
  return SyncCoordinator(outbox: outbox, remote: remote).pushPending();
}

/// Headless entrypoint body: stand up Supabase + Drift in this isolate, then
/// drain the outbox. Returns `false` on init failure so WorkManager reschedules
/// with backoff.
///
/// Runs in a separate isolate from the app, so it cannot touch the Riverpod
/// tree — it rebuilds the minimal push stack (config → Supabase → Drift →
/// outbox → gateway) from scratch and closes the database in `finally`.
Future<bool> runBackgroundSyncPush() async {
  AppDatabase? db;
  try {
    final config = BackendConfig.fromEnvironment();
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabasePublishableKey,
    );
    db = AppDatabase();
    final outbox = SyncOutboxRepo(db);
    await outbox.hydratePending();
    if (outbox.loadPending().isEmpty) return true;

    final remote = SupabaseRemotePantryRepository(
      Supabase.instance.client,
      apiBaseUrl: config.apiBaseUrl,
    );
    await drainOutbox(outbox: outbox, remote: remote);
    return true;
  } catch (error, stackTrace) {
    // The background isolate has no Flutter error boundary; an uncaught throw
    // would crash the task with no trace. Surface it (visible in device logs)
    // and signal failure so WorkManager retries on its own backoff schedule.
    developer.log(
      'Background sync push failed',
      name: 'fresh_pantry.sync',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  } finally {
    await db?.close();
  }
}

/// WorkManager callback dispatcher. Must be a top-level function annotated with
/// `@pragma('vm:entry-point')` so the background isolate can resolve it.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != backgroundSyncTask) return true;
    return runBackgroundSyncPush();
  });
}
