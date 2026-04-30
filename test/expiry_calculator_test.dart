import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/utils/expiry_calculator.dart';

void main() {
  group('calendarDaysBetween', () {
    test('compares calendar dates instead of elapsed hours', () {
      final lateNight = DateTime(2026, 4, 24, 23, 45);
      final nextMorning = DateTime(2026, 4, 25, 0, 15);

      expect(calendarDaysBetween(lateNight, nextMorning), 1);
    });
  });

  group('daysUntilExpiry', () {
    test('counts tomorrow as one day regardless of current time', () {
      final now = DateTime(2026, 4, 24, 16, 30);
      final tomorrowFromDatePicker = DateTime(2026, 4, 25);

      expect(daysUntilExpiry(tomorrowFromDatePicker, now: now), 1);
    });
  });

  group('expiryFreshness', () {
    test('keeps full freshness for a seven day shelf life on the same day', () {
      final createdAt = DateTime(2026, 4, 24, 9);
      final savedAt = DateTime(2026, 4, 24, 17);
      final expiryDate = createdAt.add(const Duration(days: 7));

      expect(
        expiryFreshness(
          expiryDate: expiryDate,
          totalShelfLifeDays: 7,
          now: savedAt,
        ),
        1.0,
      );
    });
  });

  group('freshnessStateForExpiry', () {
    test('marks past expiry dates as expired regardless of freshness', () {
      final now = DateTime(2026, 4, 24, 12);
      final yesterday = DateTime(2026, 4, 23);

      expect(
        freshnessStateForExpiry(
          freshness: 1.0,
          expiryDate: yesterday,
          now: now,
        ),
        FreshnessState.expired,
      );
    });

    test('keeps same-day expiry in the expiring soon state', () {
      final now = DateTime(2026, 4, 24, 12);
      final today = DateTime(2026, 4, 24);

      expect(
        freshnessStateForExpiry(freshness: 0.0, expiryDate: today, now: now),
        FreshnessState.expiringSoon,
      );
    });
  });
}
