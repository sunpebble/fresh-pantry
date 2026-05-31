import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class InlineNumberStepper extends StatelessWidget {
  const InlineNumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.suffix,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int min;
  final int max;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(value);
    final canStep = parsed != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(
          key: const Key('stepper_minus'),
          icon: Icons.remove,
          onTap: canStep && parsed > min ? () => _bump(parsed, -1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              if (suffix != null)
                Text(
                  ' $suffix',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
            ],
          ),
        ),
        _btn(
          key: const Key('stepper_plus'),
          icon: Icons.add,
          onTap: canStep && parsed < max ? () => _bump(parsed, 1) : null,
        ),
      ],
    );
  }

  void _bump(double current, int delta) {
    final next = (current + delta).clamp(min.toDouble(), max.toDouble());
    onChanged(_format(next));
  }

  String _format(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    // Round to 2 decimals so stepping a fractional quantity never emits binary
    // float artifacts like "1.2000000000000002" into the stored quantity.
    return double.parse(n.toStringAsFixed(2)).toString();
  }

  Widget _btn({required Key key, required IconData icon, VoidCallback? onTap}) {
    return InkResponse(
      key: key,
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceContainer,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? AppColors.outline : AppColors.onSurface,
        ),
      ),
    );
  }
}
