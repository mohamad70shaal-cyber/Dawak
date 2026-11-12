import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/base/shell_controller.dart';
import '../../../core/widgets/double_back_exit.dart';
import '../admin_tabs.dart';
import 'admin_dashboard_tab.dart';
import 'admin_drawer.dart';
import 'admin_medicines_tab.dart';
import 'admin_pharmacies_tab.dart';
import 'admin_reports_tab.dart';

/// The admin shell: four tabs (dashboard, pharmacies, medicines, reports) and a drawer for the rest. Every tab-root
/// route builds this page.
class AdminShellPage extends StatelessWidget {
  const AdminShellPage({super.key});

  static IconData _icon(AdminTab t, {required bool selected}) {
    switch (t) {
      case AdminTab.dashboard:
        return selected ? Icons.dashboard_rounded : Icons.dashboard_outlined;
      case AdminTab.pharmacies:
        return selected ? Icons.local_pharmacy_rounded : Icons.local_pharmacy_outlined;
      case AdminTab.medicines:
        return selected ? Icons.medication_rounded : Icons.medication_outlined;
      case AdminTab.reports:
        return selected ? Icons.flag_rounded : Icons.flag_outlined;
    }
  }

  static String _label(AdminTab t) => 'a_tab_${t.name}'.tr;

  static Widget _view(AdminTab t) {
    switch (t) {
      case AdminTab.dashboard:
        return const AdminDashboardTab();
      case AdminTab.pharmacies:
        return const AdminPharmaciesTab();
      case AdminTab.medicines:
        return const AdminMedicinesTab();
      case AdminTab.reports:
        return const AdminReportsTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShellController shell = Get.find<ShellController>(tag: ShellTag.admin);
    return DoubleBackExit(
      onBack: () {
        if (shell.index.value != 0) {
          shell.select(0);
          return true;
        }
        return false;
      },
      child: Obx(() {
        final int i = shell.index.value.clamp(0, AdminTabs.all.length - 1);
        return Scaffold(
          appBar: AppBar(title: Text(_label(AdminTabs.all[i]))),
          drawer: const AdminDrawer(),
          body: IndexedStack(
            index: i,
            children: <Widget>[for (final AdminTab t in AdminTabs.all) _view(t)],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: shell.select,
            destinations: <NavigationDestination>[
              for (final AdminTab t in AdminTabs.all)
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
