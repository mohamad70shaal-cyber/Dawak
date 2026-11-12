import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/order.dart';
import '../controllers/customer_orders_controller.dart';
import '../customer_tabs.dart';
import '../widgets/customer_widgets.dart';

/// "My orders" tab (C-21). Tab content only.
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final CustomerOrdersController c = Get.find<CustomerOrdersController>();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Obx(() => Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: Text('c_filter_all_orders'.tr), selected: !c.activeOnly.value, onSelected: (_) => c.setActiveOnly(false)),
                    ChoiceChip(label: Text('c_filter_active_orders'.tr), selected: c.activeOnly.value, onSelected: (_) => c.setActiveOnly(true)),
                  ],
                )),
          ),
        ),
        Expanded(
          child: Obx(() => PagedListView<Order>(
                paged: c.paged,
                empty: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: c.activeOnly.value ? 'c_no_active_orders_title'.tr : 'c_no_orders'.tr,
                  message: 'c_no_orders_hint'.tr,
                  actionLabel: 'c_start_searching'.tr,
                  onAction: () => CustomerTabs.go(CustomerTabs.search),
                ),
                itemBuilder: (BuildContext context, Order o) => OrderCard(
                  order: o,
                  onTap: () async {
                    await Get.toNamed<dynamic>(AppRoutes.customerOrder(o.id));
                    c.refreshList();
                  },
                ),
              )),
        ),
      ],
    );
  }
}
