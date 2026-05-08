// test/clipboard_url_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';

void main() {
  group('ClipboardUrlDetector', () {
    test('returns null when clipboard does not contain http(s) URL', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'just plain text, no link',
      );
      expect(await d.peek(), isNull);
    });

    test('extracts first http(s) URL from text', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => '看看这个: https://lanfanapp.com/recipe/15978 很赞',
      );
      expect(await d.peek(), 'https://lanfanapp.com/recipe/15978');
    });

    test('ignored URL is suppressed within cooldown window', () async {
      var now = DateTime(2026, 5, 8, 12, 0, 0);
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'https://x/r/1',
        clock: () => now,
      );
      d.markIgnored('https://x/r/1');
      expect(await d.peek(), isNull);

      now = now.add(const Duration(minutes: 31));
      expect(await d.peek(), 'https://x/r/1');
    });
  });

  group('extractUrl', () {
    test('returns null for plain text', () {
      expect(extractUrl('no link here'), isNull);
    });
    test('grabs first URL from mixed text', () {
      expect(extractUrl('看 https://lanfanapp.com/recipe/15978 这个'),
          'https://lanfanapp.com/recipe/15978');
    });
  });
}
