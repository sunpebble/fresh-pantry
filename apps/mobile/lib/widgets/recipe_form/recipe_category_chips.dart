import 'package:flutter/material.dart';
import '../../data/recipe_presets.dart';
import '../../theme/app_theme.dart';
import '../shared/pill_chip.dart';

/// Wrapping chip row for recipe category selection.
///
/// Shows [RecipePresets.categories] plus an optional custom-value chip (if
/// [selected] is not in the preset list) and a trailing "+ 其他" chip that
/// opens an [AlertDialog] to enter a freeform category.
///
/// Uses [Wrap] so all chips are always visible (no horizontal clipping),
/// which is appropriate for a form layout.
class RecipeCategoryChips extends StatelessWidget {
  const RecipeCategoryChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const _customSentinel = '+ 其他';

  List<String> _buildCategories() {
    final base = [...RecipePresets.categories];
    if (selected.isNotEmpty && !base.contains(selected)) {
      base.add(selected);
    }
    base.add(_customSentinel);
    return base;
  }

  Future<void> _handleSelection(BuildContext context, String value) async {
    if (value == _customSentinel) {
      final custom = await _promptCustomCategory(context);
      if (custom != null && custom.isNotEmpty) {
        onChanged(custom);
      }
      return;
    }
    onChanged(value);
  }

  Future<String?> _promptCustomCategory(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const _CustomCategoryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final category in categories)
          PillChip(
            label: category,
            selected: category == selected,
            onTap: () => _handleSelection(context, category),
          ),
      ],
    );
  }
}

/// Dialog body for entering a freeform category. Kept as a StatefulWidget so the
/// [TextEditingController] is disposed in [State.dispose] — after the dialog
/// route is fully removed — rather than mid-exit-animation (which would touch a
/// disposed controller).
class _CustomCategoryDialog extends StatefulWidget {
  const _CustomCategoryDialog();

  @override
  State<_CustomCategoryDialog> createState() => _CustomCategoryDialogState();
}

class _CustomCategoryDialogState extends State<_CustomCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义分类'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '例如：日料'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
