import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/double_back_exit.dart';
import '../controllers/pharmacist_badge_controller.dart';
import '../pharmacist_tabs.dart';
import 'dashboard_tab.dart';
import 'orders_tab.dart';
import 'pos_tab.dart';
import 'products_tab.dart';
import 'settings_tab.dart';

/// The pharmacist shell: owners and managers get five tabs, cashiers four (no dashboard). Every tab-root route builds this page.
class PharmacistShellPage extends StatelessWidget {
  const PharmacistShellPage({super.key});

  static IconData _icon(PharmacistTab t, {required bool selected}) {
    switch (t) {
      case PharmacistTab.dashboard:
        return selected ? Icons.dashboard_rounded : Icons.dashboard_outlined;
      case PharmacistTab.pos:
        return selected ? Icons.point_of_sale_rounded : Icons.point_of_sale_outlined;
      case PharmacistTab.orders:
        return selected ? Icons.inventory_2_rounded : Icons.inventory_2_outlined;
      case PharmacistTab.products:
        return selected ? Icons.medication_rounded : Icons.medication_outlined;
      case PharmacistTab.settings:
        return selected ? Icons.settings_rounded : Icons.settings_outlined;
    }
  }

  static String _label(PharmacistTab t) => 'p_tab_${t.name}'.tr;

  static Widget _view(PharmacistTab t) {
    switch (t) {
      case PharmacistTab.dashboard:
        return const DashboardTab();
      case PharmacistTab.pos:
        return const PosTab();
      case PharmacistTab.orders:
        return const OrdersTab();
      case PharmacistTab.products:
        return const ProductsTab();
      case PharmacistTab.settings:
        return const SettingsTab();
    }
  }

  List<Widget> _actions(PharmacistTab tab, PharmacistBadgeController badge) {
    return <Widget>[
      if (tab == PharmacistTab.orders)
        IconButton(
          tooltip: 'p_orders_find'.tr,
          onPressed: () => Get.toNamed<dynamic>(AppRoutes.ordersFind),
          icon: const Icon(Icons.manage_search_rounded),
        ),
      if (tab == PharmacistTab.pos)
        IconButton(
          tooltip: 'p_sales_title'.tr,
          onPressed: () => Get.toNamed<dynamic>(AppRoutes.salesHistory),
          icon: const Icon(Icons.history_rounded),
        ),
      Obx(() => IconButton(
            tooltip: 'p_req_inbox_title'.tr,
            onPressed: () async {
              await Get.toNamed<dynamic>(AppRoutes.pharmacistRequests);
              badge.refreshRequests();
            },
            icon: Badge(
              isLabelVisible: badge.openRequests.value > 0,
              label: Text('${badge.openRequests.value}'),
              child: const Icon(Icons.mark_chat_unread_outlined),
            ),
          )),
      Obx(() => IconButton(
            tooltip: 'p_notifications_title'.tr,
            onPressed: () async {
              await Get.toNamed<dynamic>(AppRoutes.pharmacistNotifications);
              badge.refreshCount();
            },
            icon: Badge(
              isLabelVisible: badge.unread.value > 0,
              label: Text('${badge.unread.value}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          )),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ShellController shell = Get.find<ShellController>(tag: ShellTag.pharmacist);
    final PharmacistBadgeController badge = Get.find<PharmacistBadgeController>();
    final List<PharmacistTab> tabs = PharmacistTabs.forSession(Get.find<SessionService>());
    return DoubleBackExit(
      onBack: () {
        if (shell.index.value != 0) {
          shell.select(0);
          return true;
        }
        return false;
      },
      child: Obx(() {
        final int i = shell.index.value.clamp(0, tabs.length - 1);
        final PharmacistTab current = tabs[i];
        return Scaffold(
          appBar: AppBar(
            title: Text(_label(current)),
            actions: _actions(current, badge),
          ),
          body: IndexedStack(
            index: i,
            children: <Widget>[for (final PharmacistTab t in tabs) _view(t)],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: shell.select,
            destinations: <NavigationDestination>[
              for (final PharmacistTab t in tabs)
                NavigationDestination(
                  icon: Icon(_icon(t, selected: false)),
                  selectedIcon: Icon(_icon(t, selected: true)),
                  label: _label(t),
                ),
            ],
          ),
        );
      }),
    );
  }
}
