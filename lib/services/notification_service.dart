import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/scheduled_notification.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _permissionGranted = false;

  bool get isInitialized => _initialized;
  bool get permissionGranted => _permissionGranted;

  Future<void> init({void Function(int notificationId)? onTap}) async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final id = resp.id;
        if (id != null) onTap?.call(id);
      },
    );
    _initialized = true;
  }

  /// Asks the OS for permission. Returns whether permission is granted after
  /// the call. Should be invoked only after [init].
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final ios = await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final android = await androidImpl?.requestNotificationsPermission();

    _permissionGranted = (ios ?? android ?? false);
    return _permissionGranted;
  }

  /// Schedules a single notification at the given local DateTime.
  Future<void> schedule(ScheduledNotification n) async {
    if (!_initialized || !_permissionGranted) return;
    final scheduledTz = tz.TZDateTime.from(n.scheduledAt, tz.local);
    if (scheduledTz.isBefore(tz.TZDateTime.now(tz.local))) return; // past
    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      scheduledTz,
      _notifDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedules a list — cancels existing IDs first, then writes the new set.
  Future<void> syncAll(
    List<ScheduledNotification> next, {
    required List<int> previousIds,
  }) async {
    if (!_initialized || !_permissionGranted) return;
    for (final id in previousIds) {
      await _plugin.cancel(id);
    }
    for (final n in next) {
      await schedule(n);
    }
  }

  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
  }

  NotificationDetails _notifDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'fresh_pantry_expiry',
          '临期提醒',
          channelDescription: '食材临期 / 过期推送',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  @visibleForTesting
  void debugSetState({required bool initialized, required bool permission}) {
    _initialized = initialized;
    _permissionGranted = permission;
  }
}
