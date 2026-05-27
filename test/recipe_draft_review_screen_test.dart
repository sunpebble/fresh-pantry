import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecipeDraft _stub() => RecipeDraft(
  sourceUrl: 'https://x',
  name: DraftField.ai('番茄牛腩面'),
  category: DraftField.ai('家常'),
  cookingMinutes: DraftField.ai(60),
  difficulty: DraftField.ai(3),
  description: DraftField.ai(''),
  imageUrl: const DraftField(value: null, source: DraftSource.ai),
  ingredients: [
    RecipeIngredientDraft(
      name: DraftField.ai('番茄'),
      amount: DraftField.ai('2'),
    ),
  ],
  steps: [DraftField.ai('切块')],
);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  testWidgets('shows AI-filled name and ingredients', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeDraftReviewScreen()),
      ),
    );
    expect(find.text('番茄牛腩面'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('confirm button writes to customRecipesProvider', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeDraftReviewScreen()),
      ),
    );
    await tester.tap(find.byKey(const Key('recipe_review_confirm')));
    await tester.pumpAndSettle();

    expect(container.read(customRecipesProvider).single.name, '番茄牛腩面');
  });

  testWidgets(
    'confirm keeps invalid draft visible instead of silently clearing',
    (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      container
          .read(aiDraftProvider.notifier)
          .updateRecipeDraft(
            RecipeDraft(
              sourceUrl: 'https://x',
              name: DraftField.ai(''),
              category: DraftField.ai('家常'),
              cookingMinutes: DraftField.ai(60),
              difficulty: DraftField.ai(3),
              description: DraftField.ai(''),
              imageUrl: const DraftField(value: null, source: DraftSource.ai),
              ingredients: [
                RecipeIngredientDraft(
                  name: DraftField.ai('番茄'),
                  amount: DraftField.ai('2'),
                ),
              ],
              steps: [DraftField.ai('切块')],
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RecipeDraftReviewScreen()),
        ),
      );
      await tester.tap(find.byKey(const Key('recipe_review_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(customRecipesProvider), isEmpty);
      expect(container.read(aiDraftProvider).recipeDraft, isNotNull);
      expect(find.text('请补全草稿：食谱名称'), findsOneWidget);
      expect(find.text('审核 AI 草稿'), findsOneWidget);
    },
  );

  testWidgets('discard clears aiDraftProvider', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeDraftReviewScreen()),
      ),
    );
    await tester.tap(find.byKey(const Key('recipe_review_discard')));
    await tester.pumpAndSettle();
    expect(container.read(aiDraftProvider).recipeDraft, isNull);
  });

  testWidgets('action buttons share a consistent height', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RecipeDraftReviewScreen(regenerate: (_) async {}),
        ),
      ),
    );

    final regenerate = tester.getSize(
      find.byKey(const Key('recipe_review_regenerate')),
    );
    final discard = tester.getSize(
      find.byKey(const Key('recipe_review_discard')),
    );
    final confirm = tester.getSize(
      find.byKey(const Key('recipe_review_confirm')),
    );

    expect(regenerate.height, 48);
    expect(discard.height, 48);
    expect(confirm.height, 48);
  });
}
