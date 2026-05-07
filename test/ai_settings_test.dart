import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';

void main() {
  group('AiSettings', () {
    test('isConfigured is false when any required field is empty', () {
      expect(const AiSettings(baseUrl: '', apiKey: '', model: '').isConfigured, false);
      expect(const AiSettings(baseUrl: 'https://x', apiKey: '', model: 'm').isConfigured, false);
      expect(const AiSettings(baseUrl: 'https://x', apiKey: 'k', model: '').isConfigured, false);
    });

    test('isConfigured is true when baseUrl, apiKey, model all non-empty', () {
      const s = AiSettings(baseUrl: 'https://api.openai.com/v1', apiKey: 'sk-x', model: 'gpt-4o');
      expect(s.isConfigured, true);
    });

    test('toJson / fromJson round-trip preserves all fields', () {
      const original = AiSettings(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        timeout: Duration(seconds: 90),
      );
      final round = AiSettings.fromJson(original.toJson());
      expect(round, original);
    });

    test('copyWith replaces only specified fields', () {
      const s = AiSettings(baseUrl: 'a', apiKey: 'b', model: 'c');
      expect(s.copyWith(model: 'd').model, 'd');
      expect(s.copyWith(model: 'd').apiKey, 'b');
    });

    test('default timeout is 60 seconds', () {
      expect(const AiSettings(baseUrl: 'a', apiKey: 'b', model: 'c').timeout, const Duration(seconds: 60));
    });
  });
}
