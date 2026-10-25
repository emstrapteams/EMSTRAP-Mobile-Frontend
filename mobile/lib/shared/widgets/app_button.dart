import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

enum AppButtonVariant { primary, emergency, secondary }

/// Full-width button with a built-in loading state. While [isLoading] is true
/// the button is disabled, which is what stops double submissions in the UI.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final String? loadingLabel;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final text = isLoading ? (loadingLabel ?? label) : label;
    final foreground = variant == AppButtonVariant.secondary
        ? AppColors.navy
        : Colors.white;

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 22),
        if (isLoading || icon != null) const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    );

    final callback = enabled ? onPressed : null;
    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: callback,
        child: content,
      ),
      AppButtonVariant.emergency => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emergencyRed,
          foregroundColor: Colors.white,
          // Keep the colour while loading so the action stays recognisable.
          disabledBackgroundColor: isLoading
              ? AppColors.emergencyRed.withValues(alpha: 0.75)
              : null,
          disabledForegroundColor: isLoading ? Colors.white : null,
        ),
        child: content,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy),
        child: content,
      ),
    };

    return SizedBox(
      width: double.infinity,
      child: Semantics(
        button: true,
        enabled: enabled,
        liveRegion: isLoading,
        child: button,
      ),
    );
  }
}
