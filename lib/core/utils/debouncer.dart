import 'dart:async';

import 'package:flutter/foundation.dart';

/// Delays an action until the user stops typing. Call [dispose] from the controller's `onClose`.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 350)});

  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
