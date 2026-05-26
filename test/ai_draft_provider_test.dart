import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/services/ai_client.dart';

RecipeDraft _stubRecipeDraft(String url) => RecipeDraft(
  sourceUrl: url,
  name: DraftField.ai('Test'),
  category: DraftField.ai('家常'),
  cookingMinutes: DraftField.ai(30),
  difficulty: DraftField.ai(2),
  description: DraftField.ai(''),
  imageUrl: const DraftField(value: null, source: DraftSource.ai),
  ingredients: const [],
  steps: const [],
);

IngredientDraft _stubIngredientDraft(String id) => IngredientDraft(
  id: id,
  name: DraftField.ai('牛奶'),
  quantity: DraftField.ai('1'),
  unit: DraftField.ai('盒'),
  category: DraftField.ai('乳制品'),
  storage: const DraftField(value: IconType.fridge, source: DraftSource.ai),
  shelfLifeDays: DraftField.ai(7),
);

void main() {
  test('starts as idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });

  test('runRecipeFromUrl sets running then complete on success', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiDraftProvider.notifier);
    final future = notifier.runRecipeFromUrl(
      'https://x',
      parser: (url) async => _stubRecipeDraft(url),
    );
    expect(container.read(aiDraftProvider).isRunning, true);
    await future;
    final state = container.read(aiDraftProvider);
    expect(state.isRunning, false);
    expect(state.recipeDraft?.sourceUrl, 'https://x');
  });

  test('runRecipeFromUrl sets error on parser exception', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(aiDraftProvider.notifier)
        .runRecipeFromUrl(
          'https://x',
          parser: (_) async => throw Exception('boom'),
        );
    final state = container.read(aiDraftProvider);
    expect(state.error, isNotNull);
  });

  test('runRecipeFromUrl preserves AiException subtype in state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(aiDraftProvider.notifier)
        .runRecipeFromUrl(
          'https://x',
          parser: (_) async => throw const AiAuthException('bad key'),
        );

    expect(container.read(aiDraftProvider).isRunning, isFalse);
    expect(container.read(aiDraftProvider).error, isA<AiAuthException>());
  });

  test('runIngredientsFromText wraps generic parser failures', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(aiDraftProvider.notifier)
        .runIngredientsFromText(
          '牛奶一盒',
          parser: (_) async => throw TimeoutException('slow'),
        );

    final state = container.read(aiDraftProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isA<AiParseException>());
    expect(state.ingredientSourceText, '牛奶一盒');
  });

  test(
    'runIngredientsFromImage preserves bytes and AiException errors',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final bytes = Uint8List.fromList([1, 2, 3]);

      await container
          .read(aiDraftProvider.notifier)
          .runIngredientsFromImage(
            bytes,
            parser: (_) async => throw const AiNetworkException('offline'),
          );

      final notifier = container.read(aiDraftProvider.notifier);
      expect(notifier.lastImageBytes, bytes);
      expect(container.read(aiDraftProvider).isRunning, isFalse);
      expect(container.read(aiDraftProvider).error, isA<AiNetworkException>());
    },
  );

  test('runIngredientsFromText stores drafts on success', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(aiDraftProvider.notifier)
        .runIngredientsFromText(
          '牛奶一盒',
          parser: (_) async => [_stubIngredientDraft('d1')],
        );

    final state = container.read(aiDraftProvider);
    expect(state.isRunning, isFalse);
    expect(state.ingredientDrafts?.single.id, 'd1');
  });

  test('clear resets to idle', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(aiDraftProvider.notifier);
    await n.runRecipeFromUrl(
      'https://x',
      parser: (u) async => _stubRecipeDraft(u),
    );
    n.clear();
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });

  test(
    'concurrent runRecipeFromUrl drops second call while first is in flight',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(aiDraftProvider.notifier);

      var firstCalls = 0;
      var secondCalls = 0;
      final firstCompleter = Completer<RecipeDraft>();

      // Start first; it never completes until we tell it to.
      final f1 = n.runRecipeFromUrl(
        'https://first',
        parser: (u) async {
          firstCalls++;
          return firstCompleter.future;
        },
      );
      // Start second while first is in flight; should be a no-op.
      await n.runRecipeFromUrl(
        'https://second',
        parser: (u) async {
          secondCalls++;
          return _stubRecipeDraft(u);
        },
      );
      expect(firstCalls, 1);
      expect(secondCalls, 0); // dropped

      // Complete the first.
      firstCompleter.complete(_stubRecipeDraft('https://first'));
      await f1;
      expect(
        container.read(aiDraftProvider).recipeDraft?.sourceUrl,
        'https://first',
      );
    },
  );
}
