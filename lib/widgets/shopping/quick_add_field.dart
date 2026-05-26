import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/shopping_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_snackbar.dart';

class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({super.key, this.focusNode});

  final FocusNode? focusNode;

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      final added = await ref
          .read(shoppingProvider.notifier)
          .addFromSuggestion(trimmed);
      if (!mounted) return;
      _controller.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      _showAddResult(trimmed, added);
    }
  }

  void _showAddResult(String name, bool added) {
    showAppSnackBar(
      context,
      added ? '已添加「$name」' : '「$name」已在购物清单中',
      backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: TextField(
          focusNode: widget.focusNode,
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '添加食材到清单...',
            hintStyle: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            prefixIcon: const Icon(Icons.add_circle, color: AppColors.primary),
            suffixIcon: IconButton(
              tooltip: '添加到购物清单',
              icon: const Icon(Icons.send, color: AppColors.primary, size: 20),
              onPressed: () {
                _submit(_controller.text);
              },
            ),
            filled: false,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
          onSubmitted: (value) {
            _submit(value);
          },
        ),
      ),
    );
  }
}
