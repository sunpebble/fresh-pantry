import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

class SwipeRevealDeleteAction extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final Key? deleteButtonKey;
  final double actionExtent;
  final BorderRadius borderRadius;

  const SwipeRevealDeleteAction({
    super.key,
    required this.child,
    required this.onDelete,
    this.deleteButtonKey,
    this.actionExtent = 84,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
  });

  @override
  State<SwipeRevealDeleteAction> createState() =>
      _SwipeRevealDeleteActionState();
}

class _SwipeRevealDeleteActionState extends State<SwipeRevealDeleteAction> {
  static const _animationDuration = AppDuration.normal;

  double _dragOffset = 0;
  bool _isDragging = false;
  // Stays true during the closing animation so the panel isn't removed while
  // the AnimatedContainer is still sliding back to zero.
  bool _isAnimatingClosed = false;

  bool get _isOpen => _dragOffset <= -widget.actionExtent + 0.5;
  bool get _isRevealing => _dragOffset < 0 || _isAnimatingClosed;

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final nextOffset = (_dragOffset + (details.primaryDelta ?? 0)).clamp(
      -widget.actionExtent,
      0.0,
    );

    setState(() {
      _dragOffset = nextOffset;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen =
        velocity < -350 || (_dragOffset.abs() > widget.actionExtent * 0.4);
    final shouldClose = velocity > 350;
    final closing = shouldClose || !shouldOpen;

    setState(() {
      _isDragging = false;
      _isAnimatingClosed = closing && _dragOffset < 0;
      _dragOffset = closing ? 0 : -widget.actionExtent;
    });
  }

  void _handleDragCancel() {
    // Always snap closed — an interrupted gesture (e.g. parent scroll steal)
    // should never leave the delete button exposed.
    setState(() {
      _isDragging = false;
      _isAnimatingClosed = _dragOffset < 0;
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_isRevealing)
            Positioned.fill(
              key: const Key('delete_panel'),
              child: Align(
                alignment: Alignment.centerRight,
                child: IgnorePointer(
                  ignoring: !_isOpen,
                  child: Semantics(
                    button: true,
                    label: '删除',
                    child: SizedBox(
                      width: widget.actionExtent,
                      child: Material(
                        color: AppColors.error,
                        child: InkWell(
                          key: widget.deleteButtonKey,
                          onTap: widget.onDelete,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.delete_outline,
                                color: AppColors.onError,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '删除',
                                style: GoogleFonts.manrope(
                                  fontSize: AppFontSize.sm,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onError,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _isDragging ? Duration.zero : _animationDuration,
            curve: AppMotionCurves.standard,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            onEnd: () {
              if (_isAnimatingClosed) {
                setState(() {
                  _isAnimatingClosed = false;
                });
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: _handleDragCancel,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
