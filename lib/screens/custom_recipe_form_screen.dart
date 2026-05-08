import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/recipe.dart';
import '../models/recipe_draft.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/custom_recipe_provider.dart';
import '../services/ai_client.dart';
import '../services/ai_recipe_parser.dart';
import '../services/share_intent_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/recipe_form/cooking_time_row.dart';
import '../widgets/recipe_form/difficulty_stars.dart';
import '../widgets/recipe_form/recipe_category_chips.dart';
import '../widgets/recipe_form/recipe_form_card.dart';
import '../widgets/recipe_form/unit_dropdown.dart';
import '../widgets/shared/recipe_image.dart';
import 'ai_settings_screen.dart';
import 'recipe_draft_review_screen.dart';

typedef CoverImagePicker = Future<String?> Function(ImageSource source);

class CustomRecipeFormScreen extends ConsumerStatefulWidget {
  const CustomRecipeFormScreen({
    super.key,
    this.recipe,
    this.pickCoverImage,
    this.urlParserOverride,
    this.prefilledUrl,
  });

  final Recipe? recipe;
  final CoverImagePicker? pickCoverImage;
  final Future<RecipeDraft> Function(String url)? urlParserOverride;
  final String? prefilledUrl;

  @override
  ConsumerState<CustomRecipeFormScreen> createState() =>
      _CustomRecipeFormScreenState();
}

class _CustomRecipeFormScreenState
    extends ConsumerState<CustomRecipeFormScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _cookingMinutesController;
  late final TextEditingController _difficultyController;
  late final TextEditingController _descriptionController;
  late final List<_IngredientControllers> _ingredientControllers;
  late final List<_StepEntry> _stepEntries;
  final _clipboardDetector = ClipboardUrlDetector();
  String? _coverImageSource;
  bool _isSaving = false;

  bool get _isEditing => widget.recipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;

    _urlController = TextEditingController();
    if (widget.prefilledUrl != null && widget.prefilledUrl!.isNotEmpty) {
      _urlController.text = widget.prefilledUrl!;
    }
    _nameController = TextEditingController(text: recipe?.name ?? '');
    _categoryController = TextEditingController(text: recipe?.category ?? '家常');
    _cookingMinutesController = TextEditingController(
      text: recipe == null ? '' : recipe.cookingMinutes.toString(),
    );
    _difficultyController = TextEditingController(
      text: recipe?.difficulty.toString() ?? '3',
    );
    _descriptionController = TextEditingController(
      text: recipe?.description ?? '',
    );
    _coverImageSource = _normalizedImageSource(recipe?.imageUrl);
    _ingredientControllers =
        recipe?.ingredients.isNotEmpty == true
            ? recipe!.ingredients.map(_IngredientControllers.from).toList()
            : [_IngredientControllers.empty()];
    _stepEntries = recipe?.steps.isNotEmpty == true
        ? recipe!.steps.map((step) => _StepEntry(text: step)).toList()
        : [_StepEntry()];

    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferClipboardUrl());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    _cookingMinutesController.dispose();
    _difficultyController.dispose();
    _descriptionController.dispose();
    for (final ingredient in _ingredientControllers) {
      ingredient.dispose();
    }
    for (final entry in _stepEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑食谱' : '新建食谱')),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AiUrlBanner(
                controller: _urlController,
                onParse: _onParseUrl,
              ),
              _CoverImageHero(
                imageSource: _coverImageSource,
                onUpload: () => _selectCoverImage(ImageSource.gallery),
                onCamera: () => _selectCoverImage(ImageSource.camera),
                onClear: _coverImageSource == null ? null : _clearCoverImage,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: RecipeFormCard(
                  icon: Icons.restaurant_menu,
                  title: '基础信息',
                  iconBackgroundColor: AppColors.primaryFixed,
                  iconForegroundColor: AppColors.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: _fieldDecoration('食谱名称 *', hint: '例如：西红柿炒蛋'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '分类 *',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RecipeCategoryChips(
                        selected: _categoryController.text,
                        onChanged: (value) => setState(() {
                          _categoryController.text = value;
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '烹饪时间 *',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CookingTimeRow(
                        controller: _cookingMinutesController,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '难度 *',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DifficultyStars(
                        value: int.tryParse(_difficultyController.text) ?? 3,
                        onChanged: (value) => setState(() {
                          _difficultyController.text = value.toString();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _descriptionController,
                        decoration: _fieldDecoration('简介', hint: '简单描述这道菜的特色…'),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: RecipeFormCard(
                  icon: Icons.restaurant,
                  title: '食材',
                  iconBackgroundColor: AppColors.secondaryFixed,
                  iconForegroundColor: AppColors.secondary,
                  countLabel: '${_ingredientControllers.length} 项',
                  child: Column(
                    children: [
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _ingredientControllers.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item =
                                _ingredientControllers.removeAt(oldIndex);
                            _ingredientControllers.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, i) {
                          final ing = _ingredientControllers[i];
                          return Padding(
                            key: ValueKey(ing.dragKey),
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                    Icons.drag_indicator,
                                    color: AppColors.outlineVariant,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: ing.nameController,
                                    decoration: _compactDecoration('食材名称'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: ing.quantityController,
                                    decoration: _compactDecoration('用量'),
                                    textAlign: TextAlign.right,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                UnitDropdown(
                                  value: ing.unit,
                                  onChanged: (value) =>
                                      setState(() => ing.unit = value),
                                ),
                                if (i > 0)
                                  IconButton(
                                    onPressed: () => _removeIngredient(i),
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    tooltip: '移除食材',
                                    color: AppColors.error,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _addIngredient,
                        icon: const Icon(Icons.add),
                        label: const Text('添加食材'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: RecipeFormCard(
                  icon: Icons.format_list_numbered,
                  title: '步骤',
                  iconBackgroundColor: AppColors.secondaryFixed,
                  iconForegroundColor: AppColors.secondary,
                  countLabel: '${_stepEntries.length} 步',
                  child: Column(
                    children: [
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _stepEntries.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _stepEntries.removeAt(oldIndex);
                            _stepEntries.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, i) {
                          final entry = _stepEntries[i];
                          return Padding(
                            key: ValueKey(entry.dragKey),
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${i + 1}',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          color: AppColors.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: TextField(
                                    controller: entry.controller,
                                    decoration: _compactDecoration('输入下一步…'),
                                    maxLines: null,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.all(AppSpacing.xs),
                                        child: Icon(
                                          Icons.drag_indicator,
                                          color: AppColors.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    if (i > 0)
                                      IconButton(
                                        onPressed: () => _removeStep(i),
                                        icon: const Icon(Icons.remove_circle_outline),
                                        tooltip: '移除步骤',
                                        color: AppColors.error,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _addStep,
                        icon: const Icon(Icons.add),
                        label: const Text('添加步骤'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 88),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: FilledButton(
          onPressed: _isSaving ? null : _saveRecipe,
          child: const Text('保存食谱'),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String labelText, {String? hint}) {
    return InputDecoration(
      labelText: labelText,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
  }

  InputDecoration _compactDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
    );
  }

  Future<void> _maybeOfferClipboardUrl() async {
    final url = await _clipboardDetector.peek();
    if (url == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('检测到食谱链接: $url'),
        action: SnackBarAction(
          label: '导入',
          onPressed: () {
            _urlController.text = url;
            _onParseUrl();
          },
        ),
      ),
    );
    // If user dismisses without tapping, mark as ignored after a delay.
    Future<void>.delayed(const Duration(seconds: 9), () {
      if (mounted && _urlController.text != url) {
        _clipboardDetector.markIgnored(url);
      }
    });
  }

  Future<void> _onParseUrl() async {
    final url = _urlController.text.trim();
    if (!url.startsWith('http')) {
      _showError('请填入合法的 http(s) 链接');
      return;
    }
    final notifier = ref.read(aiDraftProvider.notifier);
    final parser = widget.urlParserOverride ??
        (u) => AiRecipeParser.fromUrl(
              u,
              chatFn: (msgs) => AiClient.chat(
                settings: ref.read(aiSettingsProvider),
                messages: msgs,
                responseFormat: const {'type': 'json_object'},
              ),
            );
    await notifier.runRecipeFromUrl(url, parser: parser);
    final state = ref.read(aiDraftProvider);
    if (state.error is AiNotConfiguredException) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
      return;
    }
    if (state.error != null) {
      _showError(state.error!.message);
      return;
    }
    if (state.recipeDraft == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDraftReviewScreen(
          regenerate: (sourceUrl) => notifier.runRecipeFromUrl(sourceUrl, parser: parser),
        ),
      ),
    );
  }

  Future<void> _saveRecipe() async {
    if (_isSaving) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final cookingMinutes = int.tryParse(_cookingMinutesController.text.trim());
    final difficulty = int.tryParse(_difficultyController.text.trim());
    final imageUrl = _normalizedCoverImageSource();
    final steps = _stepEntries
        .map((entry) => entry.controller.text.trim())
        .where((step) => step.isNotEmpty)
        .toList();

    final missingFields = _missingFields(
      name: name,
      category: category,
      cookingMinutes: cookingMinutes,
      difficulty: difficulty,
      steps: steps,
    );
    if (missingFields.isNotEmpty) {
      _showMissingFields(missingFields);
      return;
    }

    if (imageUrl != null && !_isSupportedImageSource(imageUrl)) {
      _showError('请选择有效图片');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final validCookingMinutes = cookingMinutes!;
    final validDifficulty = difficulty!;
    final ingredients = _completeIngredients();
    final recipe = Recipe(
      id:
          widget.recipe?.id ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: category,
      difficulty: validDifficulty,
      cookingMinutes: validCookingMinutes,
      description: _descriptionController.text.trim(),
      ingredients: ingredients,
      steps: steps,
      tags: widget.recipe?.tags ?? const [],
      imageUrl: imageUrl,
    );

    try {
      final notifier = ref.read(customRecipesProvider.notifier);
      if (_isEditing) {
        await notifier.update(widget.recipe!.id, recipe);
      } else {
        await notifier.add(recipe);
      }
    } on Object {
      if (mounted) {
        _showError('保存失败，请重试');
        setState(() {
          _isSaving = false;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _addIngredient() {
    setState(() {
      _ingredientControllers.add(_IngredientControllers.empty());
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredientControllers.removeAt(index).dispose();
    });
  }

  void _addStep() {
    setState(() {
      _stepEntries.add(_StepEntry());
    });
  }

  void _removeStep(int index) {
    setState(() {
      _stepEntries.removeAt(index).dispose();
    });
  }

  Future<void> _selectCoverImage(ImageSource source) async {
    try {
      final imageSource = await _pickCoverImage(source);
      if (imageSource == null || !mounted) {
        return;
      }
      setState(() {
        _coverImageSource = imageSource;
      });
    } on Object {
      if (mounted) {
        _showError(source == ImageSource.camera ? '无法拍照，请检查权限' : '无法读取图片');
      }
    }
  }

  Future<String?> _pickCoverImage(ImageSource source) async {
    final injectedPicker = widget.pickCoverImage;
    if (injectedPicker != null) {
      return injectedPicker(source);
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (image == null) {
      return null;
    }

    final bytes = await image.readAsBytes();
    final mimeType = _mimeTypeForImage(image);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  String _mimeTypeForImage(XFile image) {
    final mimeType = image.mimeType;
    if (mimeType != null && mimeType.startsWith('image/')) {
      return mimeType;
    }

    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) {
      return 'image/png';
    }
    if (name.endsWith('.webp')) {
      return 'image/webp';
    }
    if (name.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  void _clearCoverImage() {
    setState(() {
      _coverImageSource = null;
    });
  }

  String? _normalizedCoverImageSource() {
    return _normalizedImageSource(_coverImageSource);
  }

  String? _normalizedImageSource(String? imageSource) {
    final value = imageSource?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool _isSupportedImageSource(String imageSource) {
    if (_isDataImageSource(imageSource)) {
      return true;
    }

    final uri = Uri.tryParse(imageSource);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _isDataImageSource(String imageSource) {
    final lower = imageSource.toLowerCase();
    return lower.startsWith('data:image/') && lower.contains(';base64,');
  }

  List<String> _missingFields({
    required String name,
    required String category,
    required int? cookingMinutes,
    required int? difficulty,
    required List<String> steps,
  }) {
    return [
      ..._validateBasic(
        name: name,
        category: category,
        cookingMinutes: cookingMinutes,
        difficulty: difficulty,
      ),
      ..._validateIngredients(),
      if (steps.isEmpty) '至少一个步骤',
    ];
  }

  List<String> _validateBasic({
    required String name,
    required String category,
    required int? cookingMinutes,
    required int? difficulty,
  }) {
    return <String>[
      if (name.isEmpty) '食谱名称',
      if (category.isEmpty) '分类',
      if (cookingMinutes == null || cookingMinutes <= 0) '有效烹饪时间',
      if (difficulty == null || difficulty < 1 || difficulty > 5) '1-5 的难度',
    ];
  }

  List<String> _validateIngredients() {
    var hasAnyIngredientText = false;
    var hasCompleteIngredient = false;
    var missingIngredientName = false;
    var missingIngredientAmount = false;
    for (final ingredient in _ingredientControllers) {
      final ingredientName = ingredient.nameController.text.trim();
      final ingredientQty = ingredient.quantityController.text.trim();
      // The unit field always has a pre-selected value (default 'g') and is
      // not treated as user-entered text for "has any text" / "has amount"
      // purposes — only a non-empty quantity counts.
      final hasAmount = ingredientQty.isNotEmpty;
      if (ingredientName.isNotEmpty || hasAmount) {
        hasAnyIngredientText = true;
      }
      if (ingredientName.isNotEmpty && hasAmount) {
        hasCompleteIngredient = true;
      } else if (ingredientName.isEmpty && hasAmount) {
        missingIngredientName = true;
      } else if (ingredientName.isNotEmpty && !hasAmount) {
        missingIngredientAmount = true;
      }
    }

    return <String>[
      if (!hasCompleteIngredient && !hasAnyIngredientText) '至少一种食材',
      if (missingIngredientName) '食材名称',
      if (missingIngredientAmount) '食材用量',
    ];
  }

  List<RecipeIngredient> _completeIngredients() {
    return _ingredientControllers
        .map((ingredient) {
          final name = ingredient.nameController.text.trim();
          final quantity = ingredient.quantityController.text.trim();
          final unit = ingredient.unit.trim();
          if (name.isEmpty) return null;
          if (quantity.isEmpty && unit.isEmpty) return null;
          return RecipeIngredient(name: name, quantity: quantity, unit: unit);
        })
        .whereType<RecipeIngredient>()
        .toList();
  }

  void _showError(String message) {
    showAppSnackBar(context, message);
  }

  void _showMissingFields(List<String> fields) {
    _showError('保存前请补充：${fields.join('、')}');
  }
}

class _CoverImageHero extends StatelessWidget {
  const _CoverImageHero({
    required this.imageSource,
    required this.onUpload,
    required this.onCamera,
    required this.onClear,
  });

  final String? imageSource;
  final VoidCallback onUpload;
  final VoidCallback onCamera;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.surfaceContainerLow),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RecipeImage(
              imageSource: imageSource,
              fit: BoxFit.cover,
              fallback: const _CoverImageFallback(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0),
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.13),
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.73),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '封面图片',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: AppFontSize.xl,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _HeroImageButton(
                        icon: Icons.upload_file_outlined,
                        label: '上传图片',
                        onPressed: onUpload,
                      ),
                      _HeroImageButton(
                        icon: Icons.photo_camera_outlined,
                        label: '拍照',
                        onPressed: onCamera,
                      ),
                      if (onClear != null)
                        IconButton(
                          onPressed: onClear,
                          icon: const Icon(Icons.close),
                          tooltip: '清除图片',
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.onImageScrim,
                            side: const BorderSide(
                              color: AppColors.onImageBorderSoft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImageButton extends StatelessWidget {
  const _HeroImageButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.onPrimary,
        backgroundColor: AppColors.onImageScrim,
        side: const BorderSide(color: AppColors.onImageBorderStrong),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _CoverImageFallback extends StatelessWidget {
  const _CoverImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.add_photo_alternate_outlined,
        size: 52,
        color: AppColors.outline,
      ),
    );
  }
}

class _IngredientControllers {
  _IngredientControllers({
    required String name,
    required String quantity,
    required this.unit,
  })  : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(text: quantity),
        dragKey = UniqueKey();

  factory _IngredientControllers.empty() {
    return _IngredientControllers(name: '', quantity: '', unit: 'g');
  }

  factory _IngredientControllers.from(RecipeIngredient ingredient) {
    // When the ingredient was created with legacy `amount` only (no
    // quantity/unit), fall back to the composed amount as the quantity and
    // leave unit empty so the user can pick one.
    final hasNewShape =
        ingredient.quantity.isNotEmpty || ingredient.unit.isNotEmpty;
    return _IngredientControllers(
      name: ingredient.name,
      quantity: hasNewShape ? ingredient.quantity : ingredient.amount,
      unit: hasNewShape ? ingredient.unit : '',
    );
  }

  final TextEditingController nameController;
  final TextEditingController quantityController;
  String unit;
  final Key dragKey;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
  }
}

class _StepEntry {
  _StepEntry({String text = ''})
      : controller = TextEditingController(text: text),
        dragKey = UniqueKey();

  final TextEditingController controller;
  final Key dragKey;

  void dispose() => controller.dispose();
}

class _AiUrlBanner extends StatelessWidget {
  const _AiUrlBanner({required this.controller, required this.onParse});
  final TextEditingController controller;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨ 用 AI 一键导入',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('recipe_url_input'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 下厨房…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const Key('recipe_url_parse'),
            onPressed: onParse,
            child: const Text('解析为草稿'),
          ),
        ],
      ),
    );
  }
}
