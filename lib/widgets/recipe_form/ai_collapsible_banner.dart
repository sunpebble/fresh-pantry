import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AiCollapsibleBanner extends StatefulWidget {
  const AiCollapsibleBanner({
    super.key,
    required this.urlController,
    required this.onParse,
    this.initiallyExpanded = false,
  });

  final TextEditingController urlController;
  final VoidCallback onParse;
  final bool initiallyExpanded;

  @override
  State<AiCollapsibleBanner> createState() => AiCollapsibleBannerState();
}

class AiCollapsibleBannerState extends State<AiCollapsibleBanner> {
  late bool _expanded = widget.initiallyExpanded;

  void expand() {
    if (!_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _expanded ? _buildExpanded(context) : _buildCollapsed(context),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryFixed.withValues(alpha: 0.5),
          border: Border.all(color: AppColors.primaryFixed),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '✨ 粘贴链接，AI 自动填表',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '展开',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ 用 AI 一键导入',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.onPrimary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('recipe_url_input'),
            controller: widget.urlController,
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 下厨房…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const Key('recipe_url_parse'),
            onPressed: widget.onParse,
            child: const Text('解析为草稿'),
          ),
        ],
      ),
    );
  }
}
