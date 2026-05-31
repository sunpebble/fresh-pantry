import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_text.dart';

class AiCollapsibleBanner extends StatefulWidget {
  const AiCollapsibleBanner({
    super.key,
    required this.urlController,
    required this.onParse,
    this.initiallyExpanded = false,
    this.isLoading = false,
  });

  final TextEditingController urlController;
  final VoidCallback onParse;
  final bool initiallyExpanded;
  final bool isLoading;

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
      duration: AppDuration.slow,
      curve: AppMotionCurves.decelerate,
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
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.onPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('recipe_url_input'),
            controller: widget.urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            readOnly: widget.isLoading,
            onChanged: (value) {
              final normalized = normalizePastedRecipeUrl(value);
              if (normalized == value) return;
              widget.urlController.value = TextEditingValue(
                text: normalized,
                selection: TextSelection.collapsed(offset: normalized.length),
              );
            },
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 下厨房…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('recipe_url_parse'),
              onPressed: widget.isLoading ? null : widget.onParse,
              child: widget.isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('解析中…'),
                      ],
                    )
                  : const Text('解析并填入'),
            ),
          ),
        ],
      ),
    );
  }
}
