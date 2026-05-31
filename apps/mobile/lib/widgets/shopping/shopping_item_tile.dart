import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/shopping_item.dart';
import '../../theme/app_theme.dart';
import '../shared/fk_check_circle.dart';

class ShoppingItemTile extends StatelessWidget {
  final ShoppingItem item;
  final VoidCallback onTap;

  const ShoppingItemTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        toggled: item.isChecked,
        label: item.name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedOpacity(
            opacity: item.isChecked ? 0.6 : 1.0,
            duration: AppDuration.slow,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: item.isChecked
                    ? AppColors.surfaceContainerLow.withValues(alpha: 0.5)
                    : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  // Checkbox
                  FkCheckCircle(
                    checked: item.isChecked,
                    onTap: onTap,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  // Info
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                        decoration: item.isChecked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
