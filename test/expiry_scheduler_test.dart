import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';
import 'package:fresh_pantry/models/scheduled_notification.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/expiry_scheduler.dart';

Ingredient _ing({
  required String name,
  required DateTime expiry,
  DateTime? addedAt,
}) =>
    Ingredient(
      name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      category: FoodCategories.other, storage: IconType.fridge,
      expiryDate: expiry, addedAt: addedAt ?? DateTime(2026, 5, 1),
    );

void main() {
  group('ExpiryScheduler.compute', () {
    test('schedules per-item notification at 09:00 local D-1 before expiry', () {
      final now = DateTime(2026, 5, 15, 8, 0);
      final inventory = [_ing(name: '苹果', expiry: DateTime(2026, 5, 17))];
      const settings = ReminderSettings(
        remindD1: true, remindD3: false, remindD7: false, remindDaily: false,
      );
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(result, hasLength(1));
      expect(result.first.scheduledAt, DateTime(2026, 5, 16, 9, 0));
      expect(result.first.body, contains('苹果'));
      expect(result.first.kind, ScheduledNotificationKind.expiry);
    });

    test('skips per-item notifications whose D-N is already in the past', () {
      final now = DateTime(2026, 5, 15, 12, 0);
      final inventory = [_ing(name: '苹果', expiry: DateTime(2026, 5, 14))];
      const settings = ReminderSettings(remindD1: true, remindDaily: false);
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(result, isEmpty);
    });

    test('schedules D1 + D3 when both enabled', () {
      final now = DateTime(2026, 5, 15, 6, 0);
      final inventory = [_ing(name: '葱', expiry: DateTime(2026, 5, 20))];
      const settings = ReminderSettings(
        remindD1: true, remindD3: true, remindD7: false, remindDaily: false,
      );
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(result, hasLength(2));
      final scheduledAts = result.map((n) => n.scheduledAt).toSet();
      expect(scheduledAts, {
        DateTime(2026, 5, 19, 9, 0),
        DateTime(2026, 5, 17, 9, 0),
      });
    });

    test('daily summary scheduled once when remindDaily=true', () {
      final now = DateTime(2026, 5, 15, 8, 0);
      final inventory = <Ingredient>[];
      const settings = ReminderSettings(
        remindD1: false, remindD3: false, remindD7: false, remindDaily: true,
      );
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      final daily = result
          .where((n) => n.kind == ScheduledNotificationKind.dailySummary)
          .toList();
      expect(daily, hasLength(1));
      expect(daily.first.scheduledAt.hour, 9);
    });

    test('no notifications when ingredient lacks expiryDate', () {
      final now = DateTime(2026, 5, 15);
      final inventory = [
        Ingredient(
          name: '盐', quantity: '1', unit: '袋', imageUrl: '',
          freshnessPercent: 1, state: FreshnessState.fresh,
          category: FoodCategories.other, storage: IconType.pantry,
          expiryDate: null,
        ),
      ];
      const settings = ReminderSettings(remindD1: true);
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(
        result.where((n) => n.kind == ScheduledNotificationKind.expiry),
        isEmpty,
      );
    });

    test('deterministic IDs across calls with same input', () {
      final now = DateTime(2026, 5, 15);
      final inventory = [_ing(name: '苹果', expiry: DateTime(2026, 5, 17))];
      const settings = ReminderSettings(remindD1: true, remindDaily: false);
      final r1 = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      final r2 = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(r1.first.id, r2.first.id);
    });
  });
}
