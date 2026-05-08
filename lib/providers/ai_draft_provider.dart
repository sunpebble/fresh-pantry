import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_draft.dart';
import '../models/recipe_draft.dart';
import '../services/ai_client.dart';
import '../services/share_intent_service.dart';

@immutable
class AiDraftState {
  const AiDraftState({
    this.isRunning = false,
    this.recipeDraft,
    this.ingredientDrafts,
    this.error,
    this.recipeSourceUrl,
    this.ingredientSourceText,
  });

  const AiDraftState.idle() : this();

  final bool isRunning;
  final RecipeDraft? recipeDraft;
  final List<IngredientDraft>? ingredientDrafts;
  final AiException? error;

  // Source preserved for "重新生成 / 重新识别"
  final String? recipeSourceUrl;
  final String? ingredientSourceText;
  // Image bytes are kept on the notifier (not in state) — large payload, not for equality.

  AiDraftState copyWith({
    bool? isRunning,
    RecipeDraft? recipeDraft,
    List<IngredientDraft>? ingredientDrafts,
    AiException? error,
    String? recipeSourceUrl,
    String? ingredientSourceText,
  }) =>
      AiDraftState(
        isRunning: isRunning ?? this.isRunning,
        recipeDraft: recipeDraft ?? this.recipeDraft,
        ingredientDrafts: ingredientDrafts ?? this.ingredientDrafts,
        error: error,
        recipeSourceUrl: recipeSourceUrl ?? this.recipeSourceUrl,
        ingredientSourceText: ingredientSourceText ?? this.ingredientSourceText,
      );

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is AiDraftState &&
          o.isRunning == isRunning &&
          o.recipeDraft == recipeDraft &&
          identical(o.ingredientDrafts, ingredientDrafts) &&
          o.error == error);

  @override
  int get hashCode => Object.hash(isRunning, recipeDraft, ingredientDrafts, error);
}

typedef RecipeUrlParser = Future<RecipeDraft> Function(String url);
typedef IngredientTextParser = Future<List<IngredientDraft>> Function(String text);
typedef IngredientImageParser = Future<List<IngredientDraft>> Function(Uint8List bytes);

class AiDraftNotifier extends Notifier<AiDraftState> {
  Uint8List? _lastImageBytes;

  @override
  AiDraftState build() => const AiDraftState.idle();

  void clear() {
    _lastImageBytes = null;
    state = const AiDraftState.idle();
  }

  Future<void> runRecipeFromUrl(String url, {required RecipeUrlParser parser}) async {
    if (state.isRunning) return;
    state = AiDraftState(isRunning: true, recipeSourceUrl: url);
    try {
      final draft = await parser(url);
      state = state.copyWith(isRunning: false, recipeDraft: draft);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Future<void> runIngredientsFromText(String text, {required IngredientTextParser parser}) async {
    if (state.isRunning) return;
    state = AiDraftState(isRunning: true, ingredientSourceText: text);
    try {
      final drafts = await parser(text);
      state = state.copyWith(isRunning: false, ingredientDrafts: drafts);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Future<void> runIngredientsFromImage(Uint8List bytes, {required IngredientImageParser parser}) async {
    if (state.isRunning) return;
    _lastImageBytes = bytes;
    state = const AiDraftState(isRunning: true);
    try {
      final drafts = await parser(bytes);
      state = state.copyWith(isRunning: false, ingredientDrafts: drafts);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Uint8List? get lastImageBytes => _lastImageBytes;

  void updateRecipeDraft(RecipeDraft updated) =>
      state = state.copyWith(recipeDraft: updated);

  void updateIngredientDrafts(List<IngredientDraft> updated) =>
      state = state.copyWith(ingredientDrafts: updated);
}

final aiDraftProvider =
    NotifierProvider<AiDraftNotifier, AiDraftState>(AiDraftNotifier.new);

final systemShareSourceProvider = Provider<SystemShareSource>((_) {
  throw UnimplementedError('Override in main with a real SystemShareSource.');
});
