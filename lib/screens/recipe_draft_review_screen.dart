import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/draft_field.dart';
import '../models/recipe_draft.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/custom_recipe_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/shared/ai_busy_overlay.dart';
import '../widgets/shared/ai_draft_field.dart';

class RecipeDraftReviewScreen extends ConsumerWidget {
  const RecipeDraftReviewScreen({super.key, this.regenerate});

  /// Optional callback used when "重新生成" is tapped.
  /// Called with the original `sourceUrl`. If null, button is hidden.
  final Future<void> Function(String url)? regenerate;

  static const _actionButtonHeight = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiDraftProvider);
    final draft = state.recipeDraft;
    if (draft == null) {
      return const Scaffold(body: Center(child: Text('草稿已丢失')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('审核 AI 草稿')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (draft.sourceUrl != null) ...[
                Text(
                  '来源: ${draft.sourceUrl}',
                  style: const TextStyle(
                    fontSize: AppFontSize.xs,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AiDraftFieldChip<String>(
                label: '名称',
                field: draft.name,
                onChanged: (next) => _patch(ref, draft.copyWith(name: next)),
                editorBuilder: _stringEditor,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AiDraftFieldChip<String>(
                      label: '分类',
                      field: draft.category,
                      onChanged:
                          (next) => _patch(ref, draft.copyWith(category: next)),
                      editorBuilder: _stringEditor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AiDraftFieldChip<int>(
                      label: '时长 (分钟)',
                      field: draft.cookingMinutes,
                      onChanged:
                          (next) =>
                              _patch(ref, draft.copyWith(cookingMinutes: next)),
                      formatter: (v) => '$v 分钟',
                      editorBuilder: _intEditor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AiDraftFieldChip<int>(
                      label: '难度',
                      field: draft.difficulty,
                      onChanged:
                          (next) =>
                              _patch(ref, draft.copyWith(difficulty: next)),
                      formatter: (v) => '⭐' * v,
                      editorBuilder: _intEditor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '食材 · ${draft.ingredients.length} 项',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final ing in draft.ingredients)
                ListTile(
                  dense: true,
                  title: Text(ing.name.value),
                  trailing: Text(ing.amount.value),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '步骤 · ${draft.steps.length} 步',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (var i = 0; i < draft.steps.length; i++)
                ListTile(
                  dense: true,
                  title: Text('${i + 1}. ${draft.steps[i].value}'),
                ),
            ],
          ),
          if (state.isRunning) const Positioned.fill(child: AiBusyOverlay()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (regenerate != null && draft.sourceUrl != null) ...[
              SizedBox(
                height: _actionButtonHeight,
                child: OutlinedButton(
                  key: const Key('recipe_review_regenerate'),
                  style: _outlinedActionStyle(context),
                  onPressed:
                      state.isRunning
                          ? null
                          : () => regenerate!(draft.sourceUrl!),
                  child: const Text('重新生成'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              height: _actionButtonHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('recipe_review_discard'),
                      style: _outlinedActionStyle(context),
                      onPressed:
                          state.isRunning
                              ? null
                              : () {
                                ref.read(aiDraftProvider.notifier).clear();
                                Navigator.of(context).maybePop();
                              },
                      child: const Text('丢弃'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('recipe_review_confirm'),
                      style: _filledActionStyle(context),
                      onPressed:
                          state.isRunning
                              ? null
                              : () async {
                                final validationMessage =
                                    _draftValidationMessage(draft);
                                if (validationMessage != null) {
                                  showAppSnackBar(context, validationMessage);
                                  return;
                                }
                                try {
                                  await ref
                                      .read(customRecipesProvider.notifier)
                                      .add(draft.toRecipe());
                                } on Object {
                                  if (context.mounted) {
                                    showAppSnackBar(context, '保存失败，请重试');
                                  }
                                  return;
                                }
                                if (!context.mounted) return;
                                ref.read(aiDraftProvider.notifier).clear();
                                Navigator.of(context).maybePop();
                              },
                      child: const Text('确认入库'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlinedActionStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, _actionButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }

  ButtonStyle _filledActionStyle(BuildContext context) {
    return FilledButton.styleFrom(
      minimumSize: const Size(0, _actionButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }

  void _patch(WidgetRef ref, RecipeDraft next) =>
      ref.read(aiDraftProvider.notifier).updateRecipeDraft(next);

  static Widget _stringEditor(String initial, void Function(String) save) =>
      _StringEditor(initial: initial, onSave: save);

  static Widget _intEditor(int initial, void Function(int) save) =>
      _IntEditor(initial: initial, onSave: save);

  String? _draftValidationMessage(RecipeDraft draft) {
    final missing = <String>[
      if (draft.name.value.trim().isEmpty) '食谱名称',
      if (draft.category.value.trim().isEmpty) '分类',
      if (draft.cookingMinutes.value <= 0) '有效烹饪时间',
      if (draft.difficulty.value < 1 || draft.difficulty.value > 5) '1-5 的难度',
      if (!draft.ingredients.any(_hasCompleteIngredient)) '至少一种食材',
      if (!draft.steps.any((step) => step.value.trim().isNotEmpty)) '至少一个步骤',
    ];
    if (missing.isEmpty) return null;
    return '请补全草稿：${missing.join('、')}';
  }

  bool _hasCompleteIngredient(RecipeIngredientDraft ingredient) {
    return ingredient.name.value.trim().isNotEmpty &&
        ingredient.amount.value.trim().isNotEmpty;
  }
}

extension on RecipeDraft {
  RecipeDraft copyWith({
    DraftField<String>? name,
    DraftField<String>? category,
    DraftField<int>? cookingMinutes,
    DraftField<int>? difficulty,
    DraftField<String>? description,
    DraftField<String?>? imageUrl,
    List<RecipeIngredientDraft>? ingredients,
    List<DraftField<String>>? steps,
  }) => RecipeDraft(
    sourceUrl: sourceUrl,
    name: name ?? this.name,
    category: category ?? this.category,
    cookingMinutes: cookingMinutes ?? this.cookingMinutes,
    difficulty: difficulty ?? this.difficulty,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
  );
}

class _StringEditor extends StatefulWidget {
  const _StringEditor({required this.initial, required this.onSave});
  final String initial;
  final void Function(String) onSave;
  @override
  State<_StringEditor> createState() => _StringEditorState();
}

class _StringEditorState extends State<_StringEditor> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: _controller, autofocus: true),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: () => widget.onSave(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _IntEditor extends StatefulWidget {
  const _IntEditor({required this.initial, required this.onSave});
  final int initial;
  final void Function(int) onSave;
  @override
  State<_IntEditor> createState() => _IntEditorState();
}

class _IntEditorState extends State<_IntEditor> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed:
              () => widget.onSave(
                int.tryParse(_controller.text.trim()) ?? widget.initial,
              ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
