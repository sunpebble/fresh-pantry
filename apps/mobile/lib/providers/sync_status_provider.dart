import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity_provider.dart';
import 'storage_service_provider.dart';

/// Live count of operations still waiting to be pushed to the remote.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.read(syncOutboxRepoProvider).watchPendingCount();
});

/// Derived offline / pending-sync status for the status banner.
class SyncStatus {
  const SyncStatus({required this.online, required this.pendingCount});

  final bool online;
  final int pendingCount;

  bool get showBanner => !online || pendingCount > 0;
}

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final online = ref.watch(connectivityOnlineProvider).value ?? true;
  final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
  return SyncStatus(online: online, pendingCount: pending);
});
