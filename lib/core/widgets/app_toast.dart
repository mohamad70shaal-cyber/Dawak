import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Global key of the app's `ScaffoldMessenger`, so controllers can show messages without a `BuildContext`.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { success, error, info }

/// Short feedback messages. Every kind has its own icon so the meaning never depends on colour alone.
class AppToast {
  const AppToast._();

  static void success(String message) => _show(message, ToastKind.success);
  static void error(String message) => _show(message, ToastKind.error);
  static void info(String message) => _show(message, ToastKind.info);

  static void _show(String message, ToastKind kind) {
    final ScaffoldMessengerState? m = scaffoldMessengerKey.currentState;
    if (m == null || message.trim().isEmpty) return;
    final IconData icon;
    final Color color;
    switch (kind) {
      case ToastKind.success:
        icon = Icons.check_circle_rounded;
        color = AppColors.success;
      case ToastKind.error:
        icon = Icons.error_rounded;
        color = AppColors.error;
      case ToastKind.info:
        icon = Icons.info_rounded;
        color = AppColors.primary;
    }
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: kind == ToastKind.error ? 5 : 3),
        content: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ));
  }
}
