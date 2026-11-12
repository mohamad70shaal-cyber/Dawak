import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

enum AppButtonVariant { primary, secondary, text, danger }

/// The app's one button. Shows a spinner and ignores taps while [loading], so a double tap can never
/// submit twice. Always at least 48 dp tall.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// Full width (default) or hugging its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = loading ? null : onPressed;
    final Widget content = loading
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 2)),
            ],
          );

    final Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = FilledButton(onPressed: action, child: content);
      case AppButtonVariant.secondary:
        button = OutlinedButton(onPressed: action, child: content);
      case AppButtonVariant.text:
        button = TextButton(onPressed: action, child: content);
      case AppButtonVariant.danger:
        button = FilledButton(
          onPressed: action,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.onPrimary),
          child: content,
        );
    }
    final Widget sized = ConstrainedBox(constraints: const BoxConstraints(minHeight: AppDims.minTouch), child: button);
    return Semantics(
      button: true,
      enabled: action != null,
      label: loading ? '$label…' : label,
      excludeSemantics: true,
      child: expand ? SizedBox(width: double.infinity, child: sized) : sized,
    );
  }
}
