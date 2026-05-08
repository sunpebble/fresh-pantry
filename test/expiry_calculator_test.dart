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

    test('returns 0.0 when totalShelfLifeDays is zero', () {
      final now = DateTime(2026, 4, 24);
      expect(
        expiryFreshness(
          expiryDate: now.add(const Duration(days: 7)),
          totalShelfLifeDays: 0,
          now: now,
        ),
        0.0,
      );
    });

    test('returns 0.0 when totalShelfLifeDays is negative', () {
      final now = DateTime(2026, 4, 24);
      expect(
        expiryFreshness(
          expiryDate: now.add(const Duration(days: 5)),
          totalShelfLifeDays: -3,
          now: now,
        ),
        0.0,
      );
    });

    test('clamps to 0.0 once the expiry date has passed', () {
      final now = DateTime(2026, 4, 24);
      final yesterday = now.subtract(const Duration(days: 1));
      expect(
        expiryFreshness(
          expiryDate: yesterday,
          totalShelfLifeDays: 7,
          now: now,
        ),
        0.0,
      );
    });

    test('clamps to 1.0 when remaining days exceed total shelf life', () {
      final now = DateTime(2026, 4, 24);
      // shelf life is short but expiry far in the future — clamp to 1.0.
      expect(
        expiryFreshness(
          expiryDate: now.add(const Duration(days: 100)),
          totalShelfLifeDays: 7,
          now: now,
        ),
        1.0,
      );
    });

    test('handles a very large totalShelfLifeDays without overflow', () {
      final now = DateTime(2026, 4, 24);
      expect(
        expiryFreshness(
          expiryDate: now.add(const Duration(days: 365)),
          totalShelfLifeDays: 100000,
          now: now,
        ),
        closeTo(365 / 100000, 1e-6),
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
