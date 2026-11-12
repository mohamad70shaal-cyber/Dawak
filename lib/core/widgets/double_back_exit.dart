import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app_toast.dart';

/// Wrap a tab-root screen: back first runs [onBack] (return true when it handled the press, e.g. went to the
/// first tab), otherwise asks to press back again, and exits the app on the second press within 2 seconds.
class DoubleBackExit extends StatefulWidget {
  const DoubleBackExit({super.key, required this.child, this.onBack});

  final Widget child;
  final bool Function()? onBack;

  @override
  State<DoubleBackExit> createState() => _DoubleBackExitState();
}

class _DoubleBackExitState extends State<DoubleBackExit> {
  DateTime? _last;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (widget.onBack?.call() ?? false) return;
        final DateTime now = DateTime.now();
        final DateTime? last = _last;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _last = now;
        AppToast.info('press_back_again'.tr);
      },
      child: widget.child,
    );
  }
}
