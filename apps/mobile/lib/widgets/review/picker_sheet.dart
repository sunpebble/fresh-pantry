import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.subtitle});
  final T value;
  final String label;
  final String? subtitle;
}

class PickerSheet<T> extends StatelessWidget {
  const PickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T? selected;

  /// Convenience: shows the sheet and returns the chosen value (or null on dismiss).
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<PickerOption<T>> options,
    required T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (_) =>
          PickerSheet<T>(title: title, options: options, selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.hair),
                itemBuilder: (_, i) {
                  final opt = options[i];
                  final isSelected = opt.value == selected;
                  return ListTile(
                    title: Text(opt.label),
                    subtitle: opt.subtitle == null ? null : Text(opt.subtitle!),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(opt.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
