import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import 'sync_providers.dart';

/// Flushes the sync outbox when the device regains connectivity or the app
/// returns to the foreground — closing the offline-edit → reconnect gap that the
/// previous "push only on next mutation" design left open.
class SyncFlushCoordinator extends ConsumerStatefulWidget {
  const SyncFlushCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncFlushCoordinator> createState() =>
      _SyncFlushCoordinatorState();
}

class _SyncFlushCoordinatorState extends ConsumerState<SyncFlushCoordinator>
    with WidgetsBindingObserver {
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }

  void _flush() {
    // unawaited: 触发即可，内部已合并并发 + 退避。
    ref.read(syncPushPendingProvider)();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectivityOnlineProvider, (prev, next) {
      final online = next.value ?? _wasOnline;
      if (online && !_wasOnline) _flush(); // offline -> online edge
      _wasOnline = online;
    });
    return widget.child;
  }
}
