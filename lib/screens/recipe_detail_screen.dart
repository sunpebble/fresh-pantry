import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final Recipe recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    final matched = matchedIngredientCount(inventory, recipe);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // ── Hero image app bar ──
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              background: recipe.imageUrl != null
                  ? Image.network(
                      recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceContainerLow,
                        child: const Icon(Icons.restaurant, size: 64),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceContainerLow,
                      child: const Icon(Icons.restaurant, size: 64),
                    ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Title ──
                Text(
                  recipe.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recipe.description,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Meta chips ──
                Row(
                  children: [
                    _buildChip(
                      Icons.timer_outlined,
                      '${recipe.cookingMinutes}分钟',
                    ),
                    const SizedBox(width: 10),
                    _buildChip(
                      Icons.checklist,
                      '$matched/${recipe.ingredients.length} 食材已备',
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ── Ingredients ──
                Text(
                  '所需食材',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...recipe.ingredients.map((ing) {
                  final inventoryNames = inventory.map((i) => i.name).toSet();
                  final available = inventoryNames.any(
                    (name) =>
                        name.contains(ing.name) || ing.name.contains(name),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          available
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 20,
                          color: available
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${ing.name} (${ing.amount})',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              color: available
                                  ? AppColors.onSurface
                                  : AppColors.onSurfaceVariant,
                              decoration: available
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        if (available)
                          Text(
                            '库存中',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 32),

                // ── Steps ──
                Text(
                  '烹饪步骤',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...recipe.steps.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${entry.key + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              color: AppColors.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
