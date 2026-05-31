import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/frequent_item.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/fk_toast.dart';
import '../shared/cat_icon.dart';
import '../shared/category_icon.dart';
import '../shared/fk_card.dart';

class LowStockCard extends ConsumerWidget {
  const LowStockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lowStockItemsProvider);
    if (items.isEmpty) return const SizedBox.shrink();

    return FkCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber,
                color: AppColors.fkWarn,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '库存不足 (${items.length} 项)',
                style: const TextStyle(
                  fontSize: AppFontSize.lg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items.take(4)) _LowStockRow(item: item),
          if (items.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: AppSpacing.xs),
              child: Text(
                '+ 还有 ${items.length - 4} 项',
                style: const TextStyle(
                  fontSize: AppFontSize.sm,
                  color: AppColors.outline,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('low_stock_bulk_add_cta'),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text('全部加入购物清单 (${items.length})'),
              onPressed: () => runBulkLowStockAdd(context, ref, items),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared by LowStockCard and InventoryScreen (T2.3). Shows a confirm dialog
/// listing items, on confirm batches `shoppingProvider.addFromSuggestion` calls
/// and toasts the actual count added (skips duplicates).
Future<void> runBulkLowStockAdd(
  BuildContext context,
  WidgetRef ref,
  List<FrequentItem> items,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('加入购物清单 (${items.length} 项)?'),
      content: SingleChildScrollView(
        child: Text(
          items.map((i) => '${i.name} (已买 ${i.count} 次)').join('\n'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('确认加入'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final shopping = ref.read(shoppingProvider.notifier);
  var addedCount = 0;
  for (final item in items) {
    try {
      final added = await shopping.addFromSuggestion(item.name);
      if (added) addedCount++;
    } catch (_) {
      // Skip failed adds; the toast below reports the count actually added.
    }
  }
  if (!context.mounted) return;
  fkToast(context, '已加入 $addedCount 项到购物清单');
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item});
  final FrequentItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CatIcon(category: fkCategoryIdFor(item.category), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '已买 ${item.count} 次',
            style: const TextStyle(
              fontSize: AppFontSize.sm,
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}
