import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'auth_middleware.dart';

/// Every page is built through this factory so that the route guard (`AuthMiddleware`) is never forgotten
/// and transitions are uniform. Declare static routes before parameterised ones (`/x/add` before `/x/:id`).
GetPage<dynamic> appPage(
  String name,
  Widget Function() page, {
  Bindings? binding,
  Transition transition = Transition.fadeIn,
}) {
  return GetPage<dynamic>(
    name: name,
    page: page,
    binding: binding,
    middlewares: <GetMiddleware>[AuthMiddleware()],
    transition: transition,
    transitionDuration: const Duration(milliseconds: 200),
  );
}
