import 'package:flutter/foundation.dart';

@immutable
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    this.kind = ScheduledNotificationKind.expiry,
  });

  final int id;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final ScheduledNotificationKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledNotification &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          scheduledAt == other.scheduledAt &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(id, title, body, scheduledAt, kind);
}

enum ScheduledNotificationKind { expiry, dailySummary }
