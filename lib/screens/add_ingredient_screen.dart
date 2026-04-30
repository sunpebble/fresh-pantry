import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../utils/expiry_calculator.dart';
import '../widgets/shared/expiry_range_picker.dart';
import '../widgets/shared/freshness_meter.dart';
import '../services/open_food_facts_service.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({
    super.key,
    this.initialIngredient,
    this.inventoryIndex,
  }) : assert(initialIngredient == null || inventoryIndex != null);

  final Ingredient? initialIngredient;
  final int? inventoryIndex;

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
  String _resolvedImageUrl = '';

  static const _categories = FoodCategories.values;

  static const _storageLabels = {IconType.fridge: '冰箱', IconType.pantry: '食品柜'};
  static const _storageIcons = {
    IconType.fridge: Icons.kitchen,
    IconType.pantry: Icons.shelves,
  };
  static const _decimalKeyboardType = TextInputType.numberWithOptions(
    decimal: true,
  );
  static final _decimalInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
  ];

  bool get _isEditing => widget.initialIngredient != null;

  List<String> get _categoryOptions => [
    if (!_categories.contains(_selectedCategory)) _selectedCategory,
    ..._categories,
  ];

  List<String> get _unitOptions => [
    if (!FoodKnowledge.units.contains(_selectedUnit)) _selectedUnit,
    ...FoodKnowledge.units,
  ];

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

  void _save({bool navigateToInventory = false}) {
    final name = _nameController.text.trim();
    final missingFields = [if (name.isEmpty) '食材名称'];
    if (missingFields.isNotEmpty) {
      _showMissingFields(missingFields);
      return;
    }

    final quantity = _quantityController.text.trim();
    final freshness = _computedFreshness;

    final ingredient = Ingredient(
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

    if (_isEditing) {
      final index = inventoryIndexOf(
        ref.read(inventoryProvider),
        widget.initialIngredient!,
      );
      if (index == -1) {
        Navigator.of(context).maybePop();
        return;
      }
      ref.read(inventoryProvider.notifier).update(index, ingredient);
      Navigator.of(context).pop(name);
      return;
    }

    ref.read(inventoryProvider.notifier).add(ingredient);
    final addedItem = ref.read(inventoryProvider).last;

    _resetForm();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加「$name」'),
        persist: false,
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '撤销',
          textColor: AppColors.onPrimary,
          onPressed: () {
            final index = inventoryIndexOf(
              ref.read(inventoryProvider),
              addedItem,
            );
            if (index != -1) {
              ref.read(inventoryProvider.notifier).remove(index);
            }
          },
        ),
      ),
    );

    if (navigateToInventory) {
      ref.navigateToTab(1);
    }
  }

  void _showMissingFields(List<String> fields) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('保存前请补充：${fields.join('、')}'),
        persist: false,
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frequentItems = ref.watch(frequentItemsProvider);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              _isEditing ? '编辑食材' : '策划您的食材库',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isEditing ? '更新库存中的食材信息。' : '添加新食材到您的收藏。',
              style: GoogleFonts.manrope(
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // ── Frequent items ──
            if (!_isEditing && frequentItems.isNotEmpty) ...[
              _buildLabel('常购食材'),
              const SizedBox(height: 10),
              _buildFrequentChips(frequentItems),
              const SizedBox(height: 28),
            ],

            // Ingredient Name
            _buildLabel('食材名称'),
            const SizedBox(height: 8),
            _buildFilledInput(
              controller: _nameController,
              hintText: '例如：牛奶、鸡蛋、番茄...',
              fontSize: 18,
            ),
            if (_autoFilled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '已智能填充分类、存储位置和保质期',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Category + Storage (side by side)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('分类'),
                      const SizedBox(height: 8),
                      _buildCategoryDropdown(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('存储位置'),
                      const SizedBox(height: 8),
                      _buildStorageSelector(),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Quantity + Unit (side by side)
            _buildLabel('数量'),
            const SizedBox(height: 8),
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
                const SizedBox(width: 12),
                Expanded(flex: 1, child: _buildUnitDropdown()),
              ],
            ),

            const SizedBox(height: 24),

            // Expiration Section
            _buildExpirationSection(),

            const SizedBox(height: 32),

            // Save Buttons
            _buildSaveButton(),
            const SizedBox(height: 12),
            _buildDiscardButton(),
          ],
        ),
      ),
    );
  }

  // ─── Sub-widgets ────────────────────────────────────────────────────

  Widget _buildFrequentChips(List<FrequentItem> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          GestureDetector(
            onTap: () {
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
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _storageIcons[item.storage],
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.name,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: [
            for (final category in _categoryOptions)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IconType>(
          value: _selectedStorage,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: [
            for (final type in IconType.values)
              DropdownMenuItem(
                value: type,
                child: Row(
                  children: [
                    Icon(
                      _storageIcons[type],
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(_storageLabels[type]!),
                  ],
                ),
              ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedUnit,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: [
            for (final unit in _unitOptions)
              DropdownMenuItem(value: unit, child: Text(unit)),
          ],
          onChanged: (v) => setState(() => _selectedUnit = v!),
        ),
      ),
    );
  }

  Widget _buildExpirationSection() {
    final computedFreshness = _computedFreshness;
    final expiryLabel = _expiryLabel;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
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
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        computedFreshness > 0.5
                            ? AppColors.primaryFixed
                            : computedFreshness > 0.2
                            ? AppColors.secondaryContainer
                            : AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    expiryLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          computedFreshness > 0.5
                              ? AppColors.primary
                              : computedFreshness > 0.2
                              ? AppColors.onSecondaryContainer
                              : AppColors.onErrorContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

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
            const SizedBox(height: 16),
            // Show selected date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedExpirySummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
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
            const SizedBox(height: 16),
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

    return GestureDetector(
      onTap: () => _applyShelfDays(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border:
              isSuggested && !isSelected
                  ? Border.all(color: AppColors.primary, width: 1.5)
                  : null,
        ),
        child: Text(
          '$days天后',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateChip() {
    final isCustom = _usesCustomDateRange;

    return GestureDetector(
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isCustom ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: isCustom ? AppColors.onPrimary : AppColors.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              '自定义',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCustom ? AppColors.onPrimary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: () => _save(),
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
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isEditing ? Icons.check_circle : Icons.add_circle,
              color: AppColors.onPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              _isEditing ? '保存修改' : '保存',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDiscard() {
    if (_nameController.text.isEmpty && _quantityController.text.isEmpty) {
      _discardChanges();
      return;
    }
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '丢弃更改',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              '确定要丢弃当前填写的食材信息吗？',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _discardChanges();
                },
                child: Text(
                  '丢弃',
                  style: GoogleFonts.manrope(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
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

  // ─── Shared helpers ─────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
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
    return Focus(
      skipTraversal: true,
      onFocusChange: (_) => setState(() {}),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: hasFocus ? AppColors.primary : AppColors.outline,
                  width: 2,
                ),
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters:
                  keyboardType == _decimalKeyboardType
                      ? _decimalInputFormatters
                      : null,
              style: GoogleFonts.manrope(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: hintText,
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
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
