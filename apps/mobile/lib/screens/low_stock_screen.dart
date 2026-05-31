import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/frequent_item.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_snackbar.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_check_circle.dart';
import '../widgets/shared/fk_top_bar.dart';

/// 库存不足(常买补货)页 — 设计稿 `screens-2.jsx::LowStockScreen`。
///
/// 数据用本 app 的「常买」启发式([lowStockItemsProvider] → [FrequentItem],
/// 即买过 ≥3 次但当前不在库的食材),沿用设计稿的视觉语言:按分类分组、逐项
/// 勾选、底部 sticky 渐变 CTA 一键加入购物清单。设计稿基于「剩余/阈值」的
/// threshold 模型,本 app 无该数据,故右栏展示真实的「买过 N 次」而非杜撰补货量。
class LowStockScreen extends ConsumerStatefulWidget {
  const LowStockScreen({super.key});

  @override
  ConsumerState<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends ConsumerState<LowStockScreen> {
  /// 选中项(按 name 标识);null 表示尚未按当前列表初始化为全选。
  Set<String>? _selected;
  bool _adding = false;

  Set<String> _syncSelection(List<FrequentItem> items) {
    final names = items.map((i) => i.name).toSet();
    if (_selected == null) return names; // 默认全选
    return _selected!.intersection(names);
  }

  Future<void> _addSelected(List<FrequentItem> chosen) async {
    if (_adding || chosen.isEmpty) return;
    setState(() => _adding = true);
    final shopping = ref.read(shoppingProvider.notifier);
    var added = 0;
    try {
      for (final item in chosen) {
        if (await shopping.addFromSuggestion(item.name)) added++;
      }
    } catch (_) {
      if (mounted) showAppSnackBar(context, '加入购物清单失败，请重试');
      return;
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      added == 0 ? '所选项目已在购物清单中' : '已添加 $added 项到购物清单',
      backgroundColor: added == 0 ? AppColors.tertiary : AppColors.primary,
    );
    ref.navigateToTab(FkTab.shopping);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(lowStockItemsProvider);
    final selected = _syncSelection(items);

    // 按 FK 分类分组,保持 provider 的 count 降序。
    final groups = <String, List<FrequentItem>>{};
    for (final item in items) {
      groups.putIfAbsent(fkCategoryIdFor(item.category), () => []).add(item);
    }

    final chosen = items.where((i) => selected.contains(i.name)).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 140),
              children: [
                FkTopBar(
                  title: '库存不足',
                  subtitle: items.isEmpty
                      ? '常买清单 · 暂无需补货'
                      : '${items.length} 项常买 · 已选 ${selected.length}',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                if (items.isEmpty)
                  const _EmptyState()
                else
                  for (final entry in groups.entries)
                    _CategoryGroup(
                      catId: entry.key,
                      items: entry.value,
                      isSelected: selected.contains,
                      onToggle: _toggle,
                    ),
              ],
            ),
            if (items.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _StickyCta(
                  count: chosen.length,
                  loading: _adding,
                  onTap: () => _addSelected(chosen),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggle(String name) {
    setState(() {
      final current =
          _selected ??
          ref.read(lowStockItemsProvider).map((i) => i.name).toSet();
      _selected = current.contains(name)
          ? (current..remove(name))
          : (current..add(name));
    });
  }
}

class _CategoryGroup extends StatelessWidget {
  final String catId;
  final List<FrequentItem> items;
  final bool Function(String name) isSelected;
  final void Function(String name) onToggle;

  const _CategoryGroup({
    required this.catId,
    required this.items,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = FkCategoryPalette.of(catId);
    final name = FkCategoryPalette.names[catId] ?? catId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: Row(
              children: [
                CatIcon(category: catId, size: 22, color: palette.ink),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${items.length} 项',
                  style: GoogleFonts.manrope(
                    fontSize: AppFontSize.sm,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _LowRow(
                    item: items[i],
                    checked: isSelected(items[i].name),
                    isLast: i == items.length - 1,
                    onToggle: () => onToggle(items[i].name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LowRow extends StatelessWidget {
  final FrequentItem item;
  final bool checked;
  final bool isLast;
  final VoidCallback onToggle;

  const _LowRow({
    required this.item,
    required this.checked,
    required this.isLast,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: checked,
      label: item.name,
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(color: AppColors.hair, width: 0.5),
                  ),
          ),
          child: Row(
            children: [
              FkCheckCircle(checked: checked, onTap: onToggle, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  item.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                '买过 ${item.count} 次',
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.xs,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyCta extends StatelessWidget {
  final int count;
  final bool loading;
  final VoidCallback onTap;
  const _StickyCta({
    required this.count,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !loading;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.surface, AppColors.surface.withValues(alpha: 0)],
          stops: const [0.6, 1.0],
        ),
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '一键加入购物清单 ($count)',
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: enabled ? AppColors.primary : AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: enabled ? AppShadows.strong : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: enabled ? Colors.white : AppColors.outline,
                  ),
                const SizedBox(width: 6),
                Text(
                  '一键加入购物清单 ($count)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 60,
      ),
      child: Center(
        child: Column(
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '暂无需补货的常买项',
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '买过 3 次以上、当前不在库的食材会出现在这里',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.sm,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
