import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/order.dart';
import '../controllers/pharmacist_orders_controller.dart';
import '../widgets/order_widgets.dart';

/// Orders tab (P-55): new / accepted / ready / history / expired.
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  static IconData _emptyIcon(OrderTab t) {
    switch (t) {
      case OrderTab.fresh:
        return Icons.mark_email_unread_outlined;
      case OrderTab.accepted:
        return Icons.thumb_up_alt_outlined;
      case OrderTab.ready:
        return Icons.shopping_bag_outlined;
      case OrderTab.history:
        return Icons.history_rounded;
      case OrderTab.expired:
        return Icons.timer_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final PharmacistOrdersController c = Get.find<PharmacistOrdersController>();
    return DefaultTabController(
      length: OrderTab.values.length,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[for (final OrderTab t in OrderTab.values) Tab(text: t.labelKey.tr)],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final OrderTab t in OrderTab.values)
                  PagedListView<Order>(
                    paged: c.pageFor(t),
                    empty: EmptyState(
                      icon: _emptyIcon(t),
                      title: 'p_orders_empty_${t.name}'.tr,
                      message: 'p_orders_empty_${t.name}_hint'.tr,
                    ),
                    itemBuilder: (BuildContext context, Order o) => OrderTile(order: o, onTap: () => c.openOrder(o)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
