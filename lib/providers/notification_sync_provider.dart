import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../models/reminder_settings.dart';
import '../models/scheduled_notification.dart';
import '../services/expiry_scheduler.dart';
import 'inventory_provider.dart';
import 'notification_service_provider.dart';
import 'reminder_settings_provider.dart';

typedef ExpiryScheduleComputer =
    List<ScheduledNotification> Function({
      required List<Ingredient> inventory,
      required ReminderSettings settings,
      required DateTime now,
    });

final expiryScheduleComputerProvider = Provider<ExpiryScheduleComputer>(
  (ref) => ExpiryScheduler.compute,
);

class NotificationSyncNotifier extends Notifier<List<int>> {
  @override
  List<int> build() {
    // Subscribe to both providers so changes invalidate this provider.
    ref.watch(inventoryProvider);
    ref.watch(reminderSettingsProvider);

    // Trigger async resync after this build completes.
    Future.microtask(_resyncSafely);

    // Return the cached previous IDs so state survives across rebuilds.
    return stateOrNull ?? const <int>[];
  }

  Future<void> _resyncSafely() async {
    try {
      await _resync();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry',
          context: ErrorDescription('while syncing expiry notifications'),
        ),
      );
    }
  }

  Future<void> _resync() async {
    final previousIds = List<int>.unmodifiable(state);
    final inventory = ref.read(inventoryProvider);
    final settings = ref.read(reminderSettingsProvider);
    final service = ref.read(notificationServiceProvider);
    if (!service.permissionGranted) return;
    final next = ref.read(expiryScheduleComputerProvider)(
      inventory: inventory,
      settings: settings,
      now: DateTime.now(),
    );
    final nextIds = next.map((n) => n.id).toList();
    await service.syncAll(next, previousIds: previousIds);
    if (state != nextIds) state = nextIds;
  }
}

final notificationSyncProvider =
    NotifierProvider<NotificationSyncNotifier, List<int>>(
      NotificationSyncNotifier.new,
    );
