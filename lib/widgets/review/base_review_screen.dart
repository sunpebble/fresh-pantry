import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

class BaseReviewScreen<T> extends StatelessWidget {
  const BaseReviewScreen({
    super.key,
    required this.title,
    required this.items,
    required this.emptyState,
    required this.itemBuilder,
    required this.bottomBar,
    this.showBottomBarWhenEmpty = false,
  });

  final String title;
  final List<T> items;
  final Widget emptyState;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final Widget bottomBar;
  final bool showBottomBarWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final isEmpty = items.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body:
          isEmpty
              ? emptyState
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                itemCount: items.length,
                separatorBuilder:
                    (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder:
                    (context, index) =>
                        itemBuilder(context, index, items[index]),
              ),
      bottomNavigationBar:
          isEmpty && !showBottomBarWhenEmpty ? null : bottomBar,
    );
  }
}
