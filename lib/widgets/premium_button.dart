import 'package:flutter/material.dart';

import '../services/app_feedback_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';

/// A premium animated button with haptic feedback.
///
/// Features:
/// - Subtle scale animation on press
/// - Loading state with spinner
/// - Disabled state
/// - Optional icon
/// - Automatic haptic feedback
class PremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final bool isOutlined;

  const PremiumButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height = 52,
    this.borderRadius,
    this.isOutlined = false,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get _isEnabled =>
      !widget.isLoading && !widget.isDisabled && widget.onPressed != null;

  void _onTapDown(TapDownDetails details) {
    if (!_isEnabled) return;
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_isEnabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _onTapCancel() {
    if (!_isEnabled) return;
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  Future<void> _onTap() async {
    if (!_isEnabled) return;

    // Trigger haptic feedback
    await AppFeedbackService.instance.tap();

    // Call the provided callback
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? AppColors.primary;
    final txtColor = widget.textColor ?? Colors.white;
    final radius = widget.borderRadius ?? BorderRadius.circular(14);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: _onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isOutlined
                ? Colors.transparent
                : (_isEnabled ? bgColor : bgColor.withValues(alpha: 0.5)),
            borderRadius: radius,
            border: widget.isOutlined
                ? Border.all(
                    color: _isEnabled ? bgColor : bgColor.withValues(alpha: 0.5),
                    width: 1.5,
                  )
                : null,
            boxShadow: _isEnabled && !widget.isOutlined
                ? [
                    BoxShadow(
                      color: bgColor.withValues(alpha: _isPressed ? 0.15 : 0.25),
                      blurRadius: _isPressed ? 4 : 8,
                      offset: Offset(0, _isPressed ? 2 : 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isOutlined ? bgColor : txtColor,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 20,
                          color: widget.isOutlined
                              ? (_isEnabled
                                  ? bgColor
                                  : bgColor.withValues(alpha: 0.5))
                              : (_isEnabled
                                  ? txtColor
                                  : txtColor.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.text,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: widget.isOutlined
                              ? (_isEnabled
                                  ? bgColor
                                  : bgColor.withValues(alpha: 0.5))
                              : (_isEnabled
                                  ? txtColor
                                  : txtColor.withValues(alpha: 0.7)),
                          fontWeight: FontWeight.w600,
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

/// A smaller premium button variant for secondary actions
class PremiumButtonSmall extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? color;

  const PremiumButtonSmall({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
  });

  @override
  State<PremiumButtonSmall> createState() => _PremiumButtonSmallState();
}

class _PremiumButtonSmallState extends State<PremiumButtonSmall>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;

    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) => _animationController.reverse(),
      onTapCancel: () => _animationController.reverse(),
      onTap: () async {
        if (widget.isLoading || widget.onPressed == null) return;
        await AppFeedbackService.instance.tap();
        widget.onPressed?.call();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16, color: color),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.text,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
