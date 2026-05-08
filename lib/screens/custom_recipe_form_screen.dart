import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final List<TextEditingController> _stepControllers;
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
      text: recipe?.difficulty.toString() ?? '1',
    );
    _descriptionController = TextEditingController(
      text: recipe?.description ?? '',
    );
    _coverImageSource = _normalizedImageSource(recipe?.imageUrl);
    _ingredientControllers =
        recipe?.ingredients.isNotEmpty == true
            ? recipe!.ingredients.map(_IngredientControllers.from).toList()
            : [_IngredientControllers.empty()];
    _stepControllers =
        recipe?.steps.isNotEmpty == true
            ? recipe!.steps
                .map((step) => TextEditingController(text: step))
                .toList()
            : [TextEditingController()];

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
    for (final stepController in _stepControllers) {
      stepController.dispose();
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '基础信息',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: _fieldDecoration('食谱名称 *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categoryController,
                      decoration: _fieldDecoration('分类 *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cookingMinutesController,
                      decoration: _fieldDecoration('烹饪时间（分钟）*'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _difficultyController,
                      decoration: _fieldDecoration('难度 1-5 *'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: _fieldDecoration('简介'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '食材',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _ingredientControllers.length; i++) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller:
                                  _ingredientControllers[i].nameController,
                              decoration: _fieldDecoration('食材名称'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller:
                                  _ingredientControllers[i].amountController,
                              decoration: _fieldDecoration('用量'),
                            ),
                          ),
                          if (i > 0)
                            IconButton(
                              onPressed: () => _removeIngredient(i),
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: '移除食材',
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _addIngredient,
                      icon: const Icon(Icons.add),
                      label: const Text('添加食材'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '步骤',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _stepControllers.length; i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _stepControllers[i],
                              decoration: _fieldDecoration('步骤 ${i + 1}'),
                              maxLines: 3,
                            ),
                          ),
                          if (i > 0)
                            IconButton(
                              onPressed: () => _removeStep(i),
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: '移除步骤',
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _addStep,
                      icon: const Icon(Icons.add),
                      label: const Text('添加步骤'),
                    ),
                    const SizedBox(height: 88),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isSaving ? null : _saveRecipe,
          child: const Text('保存食谱'),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String labelText) {
    return InputDecoration(
      labelText: labelText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
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
    final steps =
        _stepControllers
            .map((controller) => controller.text.trim())
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
      _stepControllers.add(TextEditingController());
    });
  }

  void _removeStep(int index) {
    setState(() {
      _stepControllers.removeAt(index).dispose();
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
      final ingredientAmount = ingredient.amountController.text.trim();
      if (ingredientName.isNotEmpty || ingredientAmount.isNotEmpty) {
        hasAnyIngredientText = true;
      }
      if (ingredientName.isNotEmpty && ingredientAmount.isNotEmpty) {
        hasCompleteIngredient = true;
      } else if (ingredientName.isEmpty && ingredientAmount.isNotEmpty) {
        missingIngredientName = true;
      } else if (ingredientName.isNotEmpty && ingredientAmount.isEmpty) {
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
          final amount = ingredient.amountController.text.trim();
          if (name.isEmpty || amount.isEmpty) {
            return null;
          }
          return RecipeIngredient(name: name, amount: amount);
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
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                            backgroundColor: const Color(0x33000000),
                            side: const BorderSide(color: Color(0x99FFFFFF)),
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
        foregroundColor: Colors.white,
        backgroundColor: const Color(0x33000000),
        side: const BorderSide(color: Color(0xB3FFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
  _IngredientControllers({required String name, required String amount})
    : nameController = TextEditingController(text: name),
      amountController = TextEditingController(text: amount);

  factory _IngredientControllers.empty() {
    return _IngredientControllers(name: '', amount: '');
  }

  factory _IngredientControllers.from(RecipeIngredient ingredient) {
    return _IngredientControllers(
      name: ingredient.name,
      amount: ingredient.amount,
    );
  }

  final TextEditingController nameController;
  final TextEditingController amountController;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class _AiUrlBanner extends StatelessWidget {
  const _AiUrlBanner({required this.controller, required this.onParse});
  final TextEditingController controller;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0EA5E9)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨ 用 AI 一键导入',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('recipe_url_input'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 小红书…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
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
