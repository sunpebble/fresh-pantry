import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../backend/backend_config_provider.dart';
import '../backend/supabase_client_provider.dart';
import '../providers/storage_service_provider.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';

/// Root-container backing for [selectedHouseholdIdProvider]. `AuthGateScreen`
/// projects the session's active household here.
///
/// It MUST live in the root container (not be injected through a nested
/// `ProviderScope` override): the global notifiers (inventory, shopping, custom
/// recipes) are root-stored, so a nested override never reaches them — their
/// `enqueueSync` would read the root default, silently no-op (empty household →
/// no enqueue → no push), and added items would never reach other members.
final selectedHouseholdIdStateProvider = StateProvider<String>((ref) => '');

/// The household every notifier syncs to, or empty in local-only mode.
///
/// A thin read seam over [selectedHouseholdIdStateProvider] so tests can pin a
/// household with `overrideWithValue` without driving a full session.
final selectedHouseholdIdProvider = Provider<String>(
  (ref) => ref.watch(selectedHouseholdIdStateProvider),
);

final syncClientIdProvider = Provider<String>((ref) => 'local-client');

final remotePantryRepositoryProvider = Provider<RemotePantryRepository>((ref) {
  final backendConfig = ref.read(backendConfigProvider);
  return SupabaseRemotePantryRepository(
    ref.read(supabaseClientProvider),
    apiBaseUrl: backendConfig.apiBaseUrl,
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final remote = ref.read(remotePantryRepositoryProvider);
  if (remote is! RemoteSyncGateway) {
    throw StateError('Remote pantry repository does not support sync pushes.');
  }
  return SyncCoordinator(
    outbox: ref.read(syncOutboxRepoProvider),
    remote: remote as RemoteSyncGateway,
  );
});

final syncPushPendingProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(syncCoordinatorProvider).pushPending();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry.sync',
          context: ErrorDescription('while pushing household sync operations'),
        ),
      );
    }
  };
});
