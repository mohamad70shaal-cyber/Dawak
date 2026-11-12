import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Selected tab of a tab shell (customer: 4 tabs, pharmacist: 5, admin: 4). Registered with `tag: ShellTag.customer` /
/// `ShellTag.pharmacist` / `ShellTag.admin` so any screen can switch tabs through [Nav].
class ShellController extends GetxController {
  ShellController(this.tabCount, {int initial = 0}) : index = initial.obs;

  final int tabCount;
  final RxInt index;

  void select(int i) {
    if (i < 0 || i >= tabCount) return;
    index.value = i;
  }
}

class ShellTag {
  const ShellTag._();

  static const String customer = 'customer';
  static const String pharmacist = 'pharmacist';
  static const String admin = 'admin';
}

/// Replaces the whole navigation stack with [route]. Controllers take this as a constructor parameter so unit
/// tests can record navigation instead of needing a running app.
typedef OffAll = void Function(String route, {Object? arguments});

void defaultOffAll(String route, {Object? arguments}) => Get.offAllNamed<dynamic>(route, arguments: arguments);

class Nav {
  const Nav._();

  /// Pops back to the shell and selects [tab]. Use this instead of pushing a tab-root route a second time.
  static void toTab(String shellTag, int tab) {
    Get.until((Route<dynamic> r) => r.isFirst);
    if (Get.isRegistered<ShellController>(tag: shellTag)) {
      Get.find<ShellController>(tag: shellTag).select(tab);
    }
  }
}
