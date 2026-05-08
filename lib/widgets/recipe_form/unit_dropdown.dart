import 'package:flutter/material.dart';
import '../../data/recipe_presets.dart';
import '../../theme/app_theme.dart';
import '../shared/pill_chip.dart';

class UnitDropdown extends StatelessWidget {
  const UnitDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxHeight: double.infinity),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final unit in RecipePresets.units)
                ListTile(
                  title: Text(unit),
                  trailing: unit == value ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(sheetContext).pop(unit),
                ),
              const Divider(height: 1),
              ListTile(
                title: const Text('自定义…'),
                leading: const Icon(Icons.edit_outlined),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final custom = await _promptCustomUnit(context);
                  if (custom != null && custom.isNotEmpty) {
                    onChanged(custom);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  Future<String?> _promptCustomUnit(BuildContext context) {
    final controller = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义单位'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：粒'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = value.isEmpty ? '单位 ▾' : '$value ▾';
    return PillChip(
      label: label,
      onTap: () => _openSheet(context),
      backgroundColor: AppColors.surfaceContainerLowest,
      borderColor: AppColors.outlineVariant,
    );
  }
}
