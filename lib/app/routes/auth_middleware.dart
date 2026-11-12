import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/services/session_service.dart';
import 'route_policy.dart';

/// Applies [RoutePolicy] to every named navigation. Attached to every page by `AppPages`.
class AuthMiddleware extends GetMiddleware {
  AuthMiddleware({super.priority = 1});

  @override
  RouteSettings? redirect(String? route) {
    if (route == null) return null;
    if (!Get.isRegistered<SessionService>()) return null;
    final SessionService session = Get.find<SessionService>();
    final String? target = RoutePolicy.redirectFor(route, session.snapshot);
    if (target == null) return null;
    session.rememberBlockedTarget(route);
    final String path = RoutePolicy.normalize(route);
    if (path == RoutePolicy.normalize(target)) return null; // never loop
    return RouteSettings(name: target);
  }
}
