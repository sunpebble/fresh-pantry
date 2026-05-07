import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/normalize_cache_key.dart';

void main() {
  group('normalizeCacheKey', () {
    test('trims leading and trailing whitespace', () {
      expect(normalizeCacheKey('  apple  '), 'apple');
    });

    test('lowercases mixed case', () {
      expect(normalizeCacheKey('Apple Pie'), 'apple pie');
    });

    test('collapses multiple internal spaces to a single space', () {
      expect(normalizeCacheKey('apple    pie'), 'apple pie');
    });

    test('treats tabs and newlines as whitespace', () {
      expect(normalizeCacheKey('apple\tpie\nslice'), 'apple pie slice');
    });

    test('combines trim + lowercase + collapse in one pass', () {
      expect(normalizeCacheKey('   APPLE\t\tPIE\n  '), 'apple pie');
    });

    test('returns empty string for whitespace-only input', () {
      expect(normalizeCacheKey('   \t\n  '), '');
    });
  });
}
