import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/services/ai_client.dart';
import 'package:fresh_pantry/services/ai_recipe_parser.dart';

String _readFixture(String name) =>
    File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  group('AiRecipeParser.fromUrl', () {
    test('parses well-formed JSON into RecipeDraft', () async {
      final draft = await AiRecipeParser.fromUrl(
        'https://lanfanapp.com/recipe/15978',
        chatFn: (_) async => _readFixture('recipe_lanfan_15978.json'),
      );
      expect(draft.name.value, '番茄牛腩面');
      expect(draft.cookingMinutes.value, 60);
      expect(draft.ingredients.length, 3);
      expect(draft.steps.length, 4);
      expect(draft.name.source, DraftSource.ai);
      expect(draft.sourceUrl, 'https://lanfanapp.com/recipe/15978');
    });

    test('extracts JSON from markdown code block when AI replies with prose', () async {
      final draft = await AiRecipeParser.fromUrl(
        'https://x',
        chatFn: (_) async => _readFixture('recipe_invalid.txt'),
      );
      expect(draft.name.value, '番茄牛腩面');
    });

    test('throws AiParseException on partial fields', () async {
      expect(
        () => AiRecipeParser.fromUrl(
          'https://x',
          chatFn: (_) async => _readFixture('recipe_partial_fields.json'),
        ),
        throwsA(isA<AiParseException>()),
      );
    });

    test('rethrows AiAuthException from chatFn', () async {
      expect(
        () => AiRecipeParser.fromUrl(
          'https://x',
          chatFn: (_) async => throw const AiAuthException('401'),
        ),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
