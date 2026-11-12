import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/widgets/double_back_exit.dart';
import '../controllers/cart_controller.dart';
import '../controllers/notification_badge_controller.dart';
import '../customer_tabs.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'profile_tab.dart';
import 'search_tab.dart';

/// The customer shell (X-01): four tabs kept alive in an IndexedStack. The four tab-root routes all build this
/// page; only the initial tab differs.
class CustomerShellPage extends StatelessWidget {
  const CustomerShellPage({super.key});

  static const List<String> _titles = <String>['c_tab_home', 'c_tab_search', 'c_tab_orders', 'c_tab_profile'];

  @override
  Widget build(BuildContext context) {
    final ShellController shell = Get.find<ShellController>(tag: ShellTag.customer);
    final CartController cart = Get.find<CartController>();
    final NotificationBadgeController badge = Get.find<NotificationBadgeController>();
    return DoubleBackExit(
      onBack: () {
        if (shell.index.value != CustomerTabs.home) {
          shell.select(CustomerTabs.home);
          return true;
        }
        return false;
      },
      child: Obx(() {
        final int i = shell.index.value;
        return Scaffold(
          appBar: AppBar(
            title: Text(i == CustomerTabs.home ? 'app_name'.tr : _titles[i].tr),
            actions: <Widget>[
              Obx(() => IconButton(
                    tooltip: 'c_notifications_title'.tr,
                    onPressed: () async {
                      await Get.toNamed<dynamic>(AppRoutes.customerNotifications);
                      badge.refreshCount();
                    },
                    icon: Badge(
                      isLabelVisible: badge.unread.value > 0,
                      label: Text('${badge.unread.value}'),
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                  )),
              Obx(() => IconButton(
                    tooltip: 'c_cart_title'.tr,
                    onPressed: () => Get.toNamed<dynamic>(AppRoutes.cart),
                    icon: Badge(
                      isLabelVisible: cart.itemCount > 0,
                      label: Text('${cart.itemCount}'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                  )),
            ],
          ),
          body: IndexedStack(
            index: i,
            children: const <Widget>[HomeTab(), SearchTab(), OrdersTab(), ProfileTab()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: shell.select,
            destinations: <NavigationDestination>[
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: 'c_tab_home'.tr),
              NavigationDestination(icon: const Icon(Icons.search_rounded), selectedIcon: const Icon(Icons.manage_search_rounded), label: 'c_tab_search'.tr),
              NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long_rounded), label: 'c_tab_orders'.tr),
              NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: 'c_tab_profile'.tr),
            ],
          ),
        );
      }),
    );
  }
}
