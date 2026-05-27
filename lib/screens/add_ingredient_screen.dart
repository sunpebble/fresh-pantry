import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/ingredient_draft.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/ai_client.dart';
import '../services/ai_ingredient_parser.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/expiry_calculator.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/expiry_range_picker.dart';
import '../widgets/shared/freshness_meter.dart';
import '../widgets/shared/pill_chip.dart';
import '../services/intake_proposal_factory.dart';
import '../services/open_food_facts_service.dart';
import 'ai_settings_screen.dart';
import 'intake_review_screen.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({
    super.key,
    this.initialIngredient,
    this.inventoryIndex,
    this.prefillOnly = false,
    this.textParserOverride,
    this.imageParserOverride,
    this.imagePicker,
  }) : assert(
         prefillOnly || initialIngredient == null || inventoryIndex != null,
       );

  final Ingredient? initialIngredient;
  final int? inventoryIndex;
  final bool prefillOnly;
  final Future<List<IngredientDraft>> Function(String text)? textParserOverride;
  final Future<List<IngredientDraft>> Function(Uint8List bytes)?
  imageParserOverride;
  final Future<Uint8List?> Function(ImageSource source)? imagePicker;

  @override
  ConsumerState<AddIngredientScreen> createState() =>
      _AddIngredientScreenState();
}

class _AddIngredientScreenState extends ConsumerState<AddIngredientScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;

  String _selectedCategory = FoodCategories.dairyAndEggs;
  IconType _selectedStorage = IconType.fridge;
  String _selectedUnit = '个';
  int? _selectedShelfDays;
  DateTime? _selectedShelfStartDate;
  DateTime? _selectedExpiryDate;
  int? _suggestedShelfDays;
  bool _autoFilled = false;
  bool _categoryManuallySelected = false;
  bool _storageManuallySelected = false;
  bool _shelfLifeManuallySelected = false;
  bool _usesCustomDateRange = false;
  bool _isSaving = false;
  String _resolvedImageUrl = '';

  static const _categories = FoodCategories.values;

  static const _decimalKeyboardType = TextInputType.numberWithOptions(
    decimal: true,
  );
  static final _decimalInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
  ];
  static final _categoryDropdownItems = _categories
      .map(
        (category) => DropdownMenuItem(value: category, child: Text(category)),
      )
      .toList(growable: false);
  static final _storageDropdownItems = IconType.values
      .map(
        (type) => DropdownMenuItem(
          value: type,
          child: Row(
            children: [
              Icon(
                storageIconFor(type),
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(storageLabelFor(type)),
            ],
          ),
        ),
      )
      .toList(growable: false);
  static final _unitDropdownItems = FoodKnowledge.units
      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
      .toList(growable: false);

  bool get _isEditing =>
      widget.initialIngredient != null && !widget.prefillOnly;

  List<DropdownMenuItem<String>> get _categoryItems {
    if (_categories.contains(_selectedCategory)) {
      return _categoryDropdownItems;
    }
    return [
      DropdownMenuItem(
        value: _selectedCategory,
        child: Text(_selectedCategory),
      ),
      ..._categoryDropdownItems,
    ];
  }

  List<DropdownMenuItem<String>> get _unitItems {
    if (FoodKnowledge.units.contains(_selectedUnit)) {
      return _unitDropdownItems;
    }
    return [
      DropdownMenuItem(value: _selectedUnit, child: Text(_selectedUnit)),
      ..._unitDropdownItems,
    ];
  }

  static DateTime? _rangeStartFor({
    required DateTime? expiryDate,
    required int? shelfDays,
  }) {
    if (expiryDate == null || shelfDays == null || shelfDays <= 0) return null;
    final expiry = DateUtils.dateOnly(expiryDate);
    return expiry.subtract(Duration(days: shelfDays));
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTimeRange _initialExpiryRange(DateTime today) {
    final selectedEnd = DateUtils.dateOnly(
      _selectedExpiryDate ?? today.add(Duration(days: _selectedShelfDays ?? 7)),
    );
    final selectedStart = DateUtils.dateOnly(
      _selectedShelfStartDate ??
          _rangeStartFor(
            expiryDate: selectedEnd,
            shelfDays:
                _selectedShelfDays ??
                calendarDaysBetween(today, selectedEnd).abs(),
          ) ??
          today,
    );

    if (selectedStart.isAfter(selectedEnd)) {
      return DateTimeRange(start: selectedEnd, end: selectedEnd);
    }
    return DateTimeRange(start: selectedStart, end: selectedEnd);
  }

  String get _selectedExpirySummary {
    final expiryDate = _selectedExpiryDate;
    if (expiryDate == null) return '';

    final startDate = _selectedShelfStartDate;
    if (_usesCustomDateRange && startDate != null) {
      return '${_formatDate(startDate)} 至 ${_formatDate(expiryDate)}';
    }
    return '到期日 ${_formatDate(expiryDate)}';
  }

  @override
  void initState() {
    super.initState();
    final initialIngredient = widget.initialIngredient;
    _nameController = TextEditingController(text: initialIngredient?.name);
    _quantityController = TextEditingController(
      text: initialIngredient?.quantity,
    );
    if (initialIngredient != null) {
      _selectedCategory =
          initialIngredient.category?.isNotEmpty == true
              ? FoodCategories.dropdownValue(initialIngredient.category)
              : _selectedCategory;
      _selectedStorage = initialIngredient.storage;
      _selectedUnit =
          initialIngredient.unit.isNotEmpty
              ? initialIngredient.unit
              : _selectedUnit;
      _selectedExpiryDate = initialIngredient.expiryDate;
      _selectedShelfDays =
          initialIngredient.shelfLifeDays ??
          (initialIngredient.expiryDate == null
              ? null
              : daysUntilExpiry(initialIngredient.expiryDate!));
      _selectedShelfStartDate = _rangeStartFor(
        expiryDate: _selectedExpiryDate,
        shelfDays: _selectedShelfDays,
      );
      _suggestedShelfDays = initialIngredient.shelfLifeDays;
      _usesCustomDateRange =
          _selectedShelfDays != null &&
          !FoodKnowledge.shelfLifePresets.contains(_selectedShelfDays);
      _resolvedImageUrl = initialIngredient.imageUrl;
      _categoryManuallySelected = true;
      _storageManuallySelected = true;
      _shelfLifeManuallySelected = true;
    }
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // ─── Smart defaults ────────────────────────────────────────────────
  Future<void> _lookupImage(String name) async {
    if (name.length < 2) return;
    try {
      final result = await OpenFoodFactsService.searchByName(name);
      if (!mounted || _nameController.text.trim() != name) return;
      setState(() {
        _resolvedImageUrl = result?.imageUrl ?? '';
      });
    } catch (_) {
      if (!mounted || _nameController.text.trim() != name) return;
      setState(() {
        _resolvedImageUrl = '';
      });
    }
  }

  void _clearResolvedImage() {
    if (_resolvedImageUrl.isEmpty) return;
    _resolvedImageUrl = '';
  }

  void _onNameChanged() {
    final name = _nameController.text.trim();
    final defaults = FoodKnowledge.lookup(name);
    if (defaults != null) {
      setState(() {
        if (!_categoryManuallySelected) {
          _selectedCategory = FoodCategories.dropdownValue(defaults.category);
        }
        if (!_storageManuallySelected) {
          _selectedStorage = defaults.storage;
        }
        _suggestedShelfDays = defaults.shelfLifeDays;
        if (!_shelfLifeManuallySelected) {
          _setShelfDays(defaults.shelfLifeDays);
        }
        _clearResolvedImage();
        _autoFilled = true;
      });
      _lookupImage(name);
    } else {
      setState(() {
        _autoFilled = false;
        _suggestedShelfDays = null;
        _clearResolvedImage();
      });
    }
  }

  void _applyShelfDays(int days) {
    setState(() {
      _shelfLifeManuallySelected = true;
      _usesCustomDateRange = false;
      _setShelfDays(days);
    });
  }

  void _setShelfDays(int days) {
    final today = DateUtils.dateOnly(DateTime.now());
    _selectedShelfDays = days;
    _selectedShelfStartDate = today;
    _selectedExpiryDate = today.add(Duration(days: days));
    _usesCustomDateRange = false;
  }

  int? get _freshnessShelfLifeDays {
    if (_selectedShelfDays != null && _selectedShelfDays! > 0) {
      return _selectedShelfDays;
    }

    final defaultShelfLifeDays =
        _suggestedShelfDays ??
        FoodKnowledge.lookup(_nameController.text.trim())?.shelfLifeDays;
    if (defaultShelfLifeDays != null && defaultShelfLifeDays > 0) {
      return defaultShelfLifeDays;
    }
    return _selectedShelfDays;
  }

  double get _computedFreshness {
    if (_selectedExpiryDate == null) {
      return widget.initialIngredient?.freshnessPercent ?? 0.85;
    }
    final days = daysUntilExpiry(_selectedExpiryDate!);
    return expiryFreshness(
      expiryDate: _selectedExpiryDate!,
      totalShelfLifeDays: _freshnessShelfLifeDays ?? days.abs(),
    );
  }

  String get _expiryLabel {
    if (_selectedExpiryDate == null) {
      return widget.initialIngredient?.expiryLabel ?? '新鲜';
    }
    return expiryLabelFor(_selectedExpiryDate!);
  }

  void _resetForm() {
    _nameController.clear();
    _quantityController.clear();
    setState(() {
      _selectedCategory = FoodCategories.dairyAndEggs;
      _selectedStorage = IconType.fridge;
      _selectedUnit = '个';
      _selectedShelfDays = null;
      _selectedShelfStartDate = null;
      _selectedExpiryDate = null;
      _suggestedShelfDays = null;
      _autoFilled = false;
      _categoryManuallySelected = false;
      _storageManuallySelected = false;
      _shelfLifeManuallySelected = false;
      _usesCustomDateRange = false;
      _resolvedImageUrl = '';
    });
  }

  Future<void> _save({bool navigateToInventory = false}) async {
    if (_isSaving) return;
    final name = _nameController.text.trim();
    final missingFields = [if (name.isEmpty) '食材名称'];
    if (missingFields.isNotEmpty) {
      _showMissingFields(missingFields);
      return;
    }

    final ingredient = _buildIngredientFromForm(name);
    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        final index = _resolveEditIndex();
        if (index == -1) {
          if (mounted) _showStaleEditSnackBar();
          return;
        }
        await ref.read(inventoryProvider.notifier).update(index, ingredient);
        if (mounted) Navigator.of(context).pop(name);
        return;
      }

      await ref.read(inventoryProvider.notifier).add(ingredient);
      final addedItem = ref.read(inventoryProvider).last;

      if (!mounted) return;
      _resetForm();

      _showAddedSnackBar(name, addedItem);

      if (navigateToInventory) {
        ref.navigateToTab(FkTab.fridge);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Ingredient _buildIngredientFromForm(String name) {
    final quantity = _quantityController.text.trim();
    final freshness = _computedFreshness;
    return Ingredient(
      name: name,
      quantity: quantity.isEmpty ? '1' : quantity,
      unit: _selectedUnit,
      imageUrl: _resolvedImageUrl,
      freshnessPercent: freshness,
      state: freshnessStateForExpiry(
        freshness: freshness,
        expiryDate: _selectedExpiryDate,
      ),
      category: _selectedCategory,
      storage: _selectedStorage,
      expiryDate: _selectedExpiryDate,
      expiryLabel: _expiryLabel,
      shelfLifeDays:
          _selectedExpiryDate == null ? null : _freshnessShelfLifeDays,
      barcode: widget.initialIngredient?.barcode,
    );
  }

  int _resolveEditIndex() {
    final initialIngredient = widget.initialIngredient!;
    final inventory = ref.read(inventoryProvider);
    final providedIndex = widget.inventoryIndex;
    if (providedIndex != null &&
        providedIndex >= 0 &&
        providedIndex < inventory.length) {
      final candidate = inventory[providedIndex];
      if (_matchesInitialIngredient(candidate, initialIngredient)) {
        return providedIndex;
      }
    }
    final identityIndex = inventory.indexWhere(
      (candidate) => identical(candidate, initialIngredient),
    );
    if (identityIndex != -1) return identityIndex;
    return inventory.indexWhere(
      (candidate) => _matchesInitialIngredient(candidate, initialIngredient),
    );
  }

  bool _matchesInitialIngredient(Ingredient candidate, Ingredient initial) {
    if (identical(candidate, initial) || candidate == initial) return true;
    return candidate.name == initial.name &&
        candidate.quantity == initial.quantity &&
        candidate.unit == initial.unit &&
        candidate.imageUrl == initial.imageUrl &&
        candidate.barcode == initial.barcode &&
        candidate.storage == initial.storage &&
        candidate.expiryDate == initial.expiryDate &&
        candidate.shelfLifeDays == initial.shelfLifeDays &&
        FoodCategories.dropdownValue(candidate.category) ==
            FoodCategories.dropdownValue(initial.category);
  }

  void _showAddedSnackBar(String name, Ingredient addedItem) {
    showAppSnackBar(
      context,
      '已添加「$name」',
      backgroundColor: AppColors.primary,
      actionLabel: '撤销',
      actionTextColor: AppColors.onPrimary,
      onAction: () {
        final index = inventoryIndexOf(ref.read(inventoryProvider), addedItem);
        if (index != -1) {
          ref.read(inventoryProvider.notifier).remove(index);
        }
      },
    );
  }

  void _showMissingFields(List<String> fields) {
    showAppSnackBar(
      context,
      '保存前请补充：${fields.join('、')}',
      backgroundColor: AppColors.error,
    );
  }

  void _showStaleEditSnackBar() {
    showAppSnackBar(
      context,
      '食材已不在库存中，无法保存修改',
      backgroundColor: AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.lg,
          AppSpacing.xxl,
          120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — FK plum-ink display, more concise than the legacy copy.
            Text(
              _isEditing ? '编辑食材' : '添加食材',
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.xxxl,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _isEditing ? '更新库存中的食材信息' : '为冰箱添加一样新食材',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.md,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ── Quick entry ──
            if (!_isEditing) ...[
              _buildQuickEntryRow(),
              const SizedBox(height: AppSpacing.xxl),
            ],

            // ── Frequent items ──
            if (!_isEditing)
              _FrequentItemsSection(onSelected: _applyFrequentItem),

            // Ingredient Name
            _buildLabel('食材名称'),
            const SizedBox(height: AppSpacing.sm),
            _buildFilledInput(
              controller: _nameController,
              hintText: '例如：牛奶、鸡蛋、番茄...',
              fontSize: AppFontSize.lg,
            ),
            if (_autoFilled) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '已智能填充分类、存储位置和保质期',
                    style: GoogleFonts.manrope(
                      fontSize: AppFontSize.sm,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),

            // Category + Storage (side by side)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('分类'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildCategoryDropdown(),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('存储位置'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildStorageSelector(),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Quantity + Unit (side by side)
            _buildLabel('数量'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFilledInput(
                    controller: _quantityController,
                    hintText: '1',
                    keyboardType: _decimalKeyboardType,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 1, child: _buildUnitDropdown()),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Expiration Section
            _buildExpirationSection(),

            const SizedBox(height: AppSpacing.huge),

            // Save Buttons
            _buildSaveButton(),
            const SizedBox(height: AppSpacing.md),
            _buildDiscardButton(),
          ],
        ),
      ),
    );
  }

  // ─── Sub-widgets ────────────────────────────────────────────────────

  void _applyFrequentItem(FrequentItem item) {
    _nameController.text = item.name;
    setState(() {
      _selectedCategory = FoodCategories.dropdownValue(item.category);
      _selectedStorage = item.storage;
      _selectedUnit = item.unit;
      if (item.shelfLifeDays != null) {
        _setShelfDays(item.shelfLifeDays!);
      }
      _autoFilled = true;
      _categoryManuallySelected = false;
      _storageManuallySelected = false;
      _shelfLifeManuallySelected = false;
    });
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(
            fontSize: AppFontSize.md,
            color: AppColors.onSurface,
          ),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: _categoryItems,
          onChanged:
              (v) => setState(() {
                _selectedCategory = v!;
                _categoryManuallySelected = true;
              }),
        ),
      ),
    );
  }

  Widget _buildStorageSelector() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IconType>(
          value: _selectedStorage,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(
            fontSize: AppFontSize.md,
            color: AppColors.onSurface,
          ),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: _storageDropdownItems,
          onChanged:
              (v) => setState(() {
                _selectedStorage = v!;
                _storageManuallySelected = true;
              }),
        ),
      ),
    );
  }

  Widget _buildUnitDropdown() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedUnit,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(
            fontSize: AppFontSize.md,
            color: AppColors.onSurface,
          ),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: _unitItems,
          onChanged: (v) => setState(() => _selectedUnit = v!),
        ),
      ),
    );
  }

  ({Color bg, Color text}) _freshnessBadgeColors(double freshness) {
    if (freshness > 0.5) {
      return (bg: AppColors.primaryFixed, text: AppColors.primary);
    }
    if (freshness > 0.2) {
      return (
        bg: AppColors.secondaryContainer,
        text: AppColors.onSecondaryContainer,
      );
    }
    return (bg: AppColors.errorContainer, text: AppColors.onErrorContainer);
  }

  Widget _buildExpirationSection() {
    final computedFreshness = _computedFreshness;
    final expiryLabel = _expiryLabel;
    final badgeColors = _freshnessBadgeColors(computedFreshness);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel('保质期'),
              if (_selectedExpiryDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColors.bg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    expiryLabel,
                    style: GoogleFonts.manrope(
                      fontSize: AppFontSize.xs,
                      fontWeight: FontWeight.w700,
                      color: badgeColors.text,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Quick-select chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in FoodKnowledge.shelfLifePresets)
                _buildShelfDayChip(days),
              _buildCustomDateChip(),
            ],
          ),

          if (_selectedExpiryDate != null) ...[
            const SizedBox(height: AppSpacing.lg),
            // Show selected date
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _selectedExpirySummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap:
                        () => setState(() {
                          _selectedShelfDays = null;
                          _selectedShelfStartDate = null;
                          _selectedExpiryDate = null;
                          _shelfLifeManuallySelected = true;
                          _usesCustomDateRange = false;
                        }),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GradientFreshnessMeter(percent: computedFreshness),
          ],
        ],
      ),
    );
  }

  Widget _buildShelfDayChip(int days) {
    final isSelected = !_usesCustomDateRange && _selectedShelfDays == days;
    final isSuggested =
        _suggestedShelfDays != null &&
        FoodKnowledge.shelfLifePresets.contains(_suggestedShelfDays) &&
        _suggestedShelfDays == days;

    return PillChip(
      label: '$days天后',
      onTap: () => _applyShelfDays(days),
      selected: isSelected,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      fontWeight: FontWeight.w700,
      backgroundColor: AppColors.surfaceContainerLowest,
      foregroundColor: AppColors.onSurface,
      borderColor: isSuggested && !isSelected ? AppColors.primary : null,
    );
  }

  Widget _buildCustomDateChip() {
    final isCustom = _usesCustomDateRange;

    return PillChip(
      label: '自定义',
      icon: Icons.calendar_today,
      iconSize: 14,
      iconLabelGap: 4,
      onTap: () async {
        final today = DateUtils.dateOnly(DateTime.now());
        final picked = await showExpiryRangePicker(
          context: context,
          initialDateRange: _initialExpiryRange(today),
          firstDate: today.subtract(const Duration(days: 1825)),
          lastDate: today.add(const Duration(days: 1825)),
          currentDate: today,
        );
        if (picked != null) {
          final start = DateUtils.dateOnly(picked.start);
          final end = DateUtils.dateOnly(picked.end);
          final shelfDays = calendarDaysBetween(start, end);
          setState(() {
            _selectedShelfStartDate = start;
            _selectedExpiryDate = end;
            _selectedShelfDays = shelfDays <= 0 ? 1 : shelfDays;
            _shelfLifeManuallySelected = true;
            _usesCustomDateRange = true;
          });
        }
      },
      selected: isCustom,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      fontWeight: FontWeight.w700,
      backgroundColor: AppColors.surfaceContainerLowest,
      foregroundColor: AppColors.onSurface,
    );
  }

  Widget _buildSaveButton() {
    return Semantics(
      button: true,
      label: _isSaving ? '保存中' : (_isEditing ? '保存修改' : '保存'),
      child: GestureDetector(
        onTap: _isSaving ? null : () => _save(),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.8),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.onPrimary),
                  ),
                )
              else
                Icon(
                  _isEditing ? Icons.check_circle : Icons.add_circle,
                  color: AppColors.onPrimary,
                ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _isSaving ? '保存中...' : (_isEditing ? '保存修改' : '保存'),
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.lg,
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_nameController.text.isEmpty && _quantityController.text.isEmpty) {
      _discardChanges();
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '丢弃更改',
      content: '确定要丢弃当前填写的食材信息吗？',
      confirmLabel: '丢弃',
      isDestructive: true,
    );
    if (!mounted || !confirmed) return;
    _discardChanges();
  }

  void _discardChanges() {
    _resetForm();
  }

  Widget _buildDiscardButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed:
            _isEditing
                ? () => Navigator.of(context).maybePop()
                : _confirmDiscard,
        child: Text(
          _isEditing ? '取消' : '丢弃',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ─── Quick entry ────────────────────────────────────────────────────

  Widget _buildQuickEntryRow() => Row(
    children: [
      Expanded(
        child: _quickButton(
          key: const Key('quick_camera'),
          icon: Icons.camera_alt_outlined,
          label: '拍照识别',
          onTap: _runCamera,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: _quickButton(
          key: const Key('quick_text'),
          icon: Icons.edit_note,
          label: '粘贴清单',
          onTap: _runTextDialog,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: _quickButton(
          key: const Key('quick_manual'),
          icon: Icons.edit,
          label: '手填',
          onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
        ),
      ),
    ],
  );

  Widget _quickButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.sm,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _runTextDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('粘贴食材清单'),
            content: TextField(
              key: const Key('quick_text_input'),
              controller: controller,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例：番茄 3 个 鸡蛋 6 颗 面条 1 把',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('quick_text_parse'),
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('解析'),
              ),
            ],
          ),
    );
    if (text == null || text.trim().isEmpty) return;
    await _runIngredientFlow(
      runner:
          () => (widget.textParserOverride ??
              (t) => AiIngredientParser.fromText(
                t,
                chatFn:
                    (msgs) => AiClient.chat(
                      settings: ref.read(aiSettingsProvider),
                      messages: msgs,
                      responseFormat: const {'type': 'json_object'},
                    ),
              ))(text.trim()),
    );
  }

  Future<void> _runCamera() async {
    final picker = widget.imagePicker ?? _defaultImagePicker;
    final bytes = await picker(ImageSource.camera);
    if (bytes == null) return;
    await _runIngredientFlow(
      runner:
          () => (widget.imageParserOverride ??
              (b) => AiIngredientParser.fromImage(
                b,
                chatFn:
                    (msgs) => AiClient.chat(
                      settings: ref.read(aiSettingsProvider),
                      messages: msgs,
                    ),
              ))(bytes),
    );
  }

  Future<Uint8List?> _defaultImagePicker(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    return image == null ? null : await image.readAsBytes();
  }

  Future<void> _runIngredientFlow({
    required Future<List<IngredientDraft>> Function() runner,
  }) async {
    try {
      final drafts = await runner();
      if (!mounted) return;
      if (drafts.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未识别到食材')));
        return;
      }
      if (drafts.length == 1) {
        final ingredient = drafts.first.toIngredient();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => AddIngredientScreen(
                  initialIngredient: ingredient,
                  prefillOnly: true,
                ),
          ),
        );
        return;
      }
      final inventory = ref.read(inventoryProvider);
      final proposals = IntakeProposalFactory.fromDrafts(drafts, inventory);
      ref.read(intakeReviewProvider.notifier).seed(proposals);
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const IntakeReviewScreen()));
    } on AiNotConfiguredException {
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
    } on AiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ─── Shared helpers ─────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: AppFontSize.sm,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildFilledInput({
    required TextEditingController controller,
    String? hintText,
    double fontSize = 16,
    TextInputType? keyboardType,
  }) {
    return _FilledInput(
      controller: controller,
      hintText: hintText,
      fontSize: fontSize,
      keyboardType: keyboardType,
      inputFormatters:
          keyboardType == _decimalKeyboardType ? _decimalInputFormatters : null,
    );
  }
}

class _FrequentItemsSection extends ConsumerWidget {
  const _FrequentItemsSection({required this.onSelected});

  final ValueChanged<FrequentItem> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(frequentItemsProvider);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('常购食材'),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              GestureDetector(
                onTap: () => onSelected(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        storageIconFor(item.storage),
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        item.name,
                        style: GoogleFonts.manrope(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxxl),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: AppFontSize.sm,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
        color: AppColors.primary,
      ),
    );
  }
}

class _FilledInput extends StatefulWidget {
  const _FilledInput({
    required this.controller,
    this.hintText,
    this.fontSize = 16,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hintText;
  final double fontSize;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_FilledInput> createState() => _FilledInputState();
}

class _FilledInputState extends State<_FilledInput> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _hasFocus ? AppColors.primary : AppColors.outline,
              width: 2,
            ),
          ),
        ),
        child: TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          style: GoogleFonts.manrope(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
          ),
        ),
      ),
    );
  }
}
