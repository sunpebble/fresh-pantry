import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class CategoryChips extends StatelessWidget {
  final List<String> categories;
  final List<String> leadingCategories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const CategoryChips({
    super.key,
    required this.categories,
    this.leadingCategories = const [],
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fixedCategory = categories.contains('全部') ? '全部' : null;
    final fixedCategories = [...leadingCategories, ?fixedCategory];
    final scrollableCategories = fixedCategory == null
        ? categories
        : categories.where((category) => category != fixedCategory).toList();

    if (fixedCategories.isNotEmpty) {
      return SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.xxl),
            for (final category in fixedCategories) ...[
              _CategoryChip(
                category: category,
                isSelected: category == selectedCategory,
                onSelected: onSelected,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (scrollableCategories.isNotEmpty) ...[
              Expanded(
                child: _ScrollableCategoryChips(
                  categories: scrollableCategories,
                  selectedCategory: selectedCategory,
                  onSelected: onSelected,
                  padding: const EdgeInsets.only(right: 24),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: _ScrollableCategoryChips(
        categories: categories,
        selectedCategory: selectedCategory,
        onSelected: onSelected,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      ),
    );
  }
}

class _ScrollableCategoryChips extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  const _ScrollableCategoryChips({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, index) {
        final category = categories[index];

        return _CategoryChip(
          category: category,
          isSelected: category == selectedCategory,
          onSelected: onSelected,
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: category,
      child: GestureDetector(
        onTap: () => onSelected(category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            category,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              height: 1.0,
              color: isSelected
                  ? AppColors.onPrimary
                  : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
