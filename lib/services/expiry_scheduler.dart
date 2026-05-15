import '../models/ingredient.dart';
import '../models/reminder_settings.dart';
import '../models/scheduled_notification.dart';

class ExpiryScheduler {
  ExpiryScheduler._();

  static const int dailySummaryHour = 9; // 09:00 local
  static const int dailySummaryId = 1; // reserved

  static List<ScheduledNotification> compute({
    required List<Ingredient> inventory,
    required ReminderSettings settings,
    required DateTime now,
  }) {
    final out = <ScheduledNotification>[];

    // Per-item D-N notifications
    for (final ing in inventory) {
      final expiry = ing.expiryDate;
      if (expiry == null) continue;
      for (final offset in settings.enabledOffsetDays) {
        final scheduledDate = DateTime(
          expiry.year, expiry.month, expiry.day - offset,
          dailySummaryHour, 0,
        );
        if (!scheduledDate.isAfter(now)) continue;
        out.add(ScheduledNotification(
          id: _idFor(ing, offset),
          title: '$offset 天后过期',
          body: '${ing.name} ${ing.quantity}${ing.unit} 还剩 $offset 天',
          scheduledAt: scheduledDate,
          kind: ScheduledNotificationKind.expiry,
        ));
      }
    }

    // Daily summary — single recurring slot
    if (settings.remindDaily) {
      final today9 = DateTime(now.year, now.month, now.day,
          dailySummaryHour, 0);
      final next = today9.isAfter(now)
          ? today9
          : today9.add(const Duration(days: 1));
      out.add(ScheduledNotification(
        id: dailySummaryId,
        title: '每日临期提醒',
        body: '查看今天到期 / 已过期食材',
        scheduledAt: next,
        kind: ScheduledNotificationKind.dailySummary,
      ));
    }

    return out;
  }

  /// Deterministic id from name + storage + addedAt + offset.
  /// Restricted to int32 range so flutter_local_notifications accepts it.
  static int _idFor(Ingredient ing, int offset) {
    final base =
        '${ing.name}|${ing.storage.name}|${ing.addedAt?.millisecondsSinceEpoch ?? 0}|$offset';
    var hash = 0;
    for (final code in base.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == dailySummaryId) hash++; // avoid collision with reserved id
    return hash;
  }
}
