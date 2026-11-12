import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/order.dart';
import '../controllers/home_controller.dart';
import '../controllers/medicine_search_controller.dart';
import '../customer_tabs.dart';
import '../widgets/customer_widgets.dart';

/// Customer home tab: greeting, search entry, category chips and current orders. Tab content only.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController c = Get.find<HomeController>();
    final MedicineSearchController search = Get.find<MedicineSearchController>();
    final TextTheme t = Theme.of(context).textTheme;
    return AsyncStateView.of(
      c,
      onRetry: c.reload,
      builder: (BuildContext context) => RefreshIndicator(
        onRefresh: c.refreshSilently,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Obx(() {
              final String name = c.displayName;
              return Text(
                name.isEmpty ? 'c_greeting_anon'.tr : 'c_greeting'.trParams(<String, String>{'name': name}),
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              );
            }),
            const SizedBox(height: 4),
            Text('c_home_subtitle'.tr, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
            const SizedBox(height: 16),
            AppTextField(
              label: 'c_search_hint'.tr,
              readOnly: true,
              prefixIcon: Icons.search_rounded,
              onTap: () => CustomerTabs.go(CustomerTabs.search),
            ),
            Obx(() {
              if (c.categories.isEmpty) return const SizedBox.shrink();
              final bool ar = isArabicNow();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 20),
                  SectionTitle('c_categories'.tr),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final MedicineCategory cat in c.categories)
                        ActionChip(
                          label: Text(cat.name(ar)),
                          onPressed: () {
                            search.applyCategory(cat.id);
                            CustomerTabs.go(CustomerTabs.search);
                          },
                        ),
                    ],
                  ),
                ],
              );
            }),
            Obx(() {
              if (c.openRequests.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 20),
                  SectionTitle(
                    'c_open_requests'.tr,
                    trailing: TextButton(onPressed: () => Get.toNamed<dynamic>(AppRoutes.customerRequests), child: Text('view_all'.tr)),
                  ),
                  for (final AvailabilityRequestSummary s in c.openRequests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RequestTile(request: s, onTap: () => Get.toNamed<dynamic>(AppRoutes.customerRequest(s.id))),
                    ),
                ],
              );
            }),
            const SizedBox(height: 20),
            SectionTitle(
              'c_active_orders'.tr,
              trailing: TextButton(onPressed: () => CustomerTabs.go(CustomerTabs.orders), child: Text('view_all'.tr)),
            ),
            Obx(() {
              if (c.activeOrders.isEmpty) {
                return InlineNotice('c_no_active_orders'.tr);
              }
              return Column(
                children: <Widget>[
                  for (final Order o in c.activeOrders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OrderCard(order: o, onTap: () => Get.toNamed<dynamic>(AppRoutes.customerOrder(o.id))),
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            InlineNotice('c_disclaimer'.tr),
          ],
        ),
      ),
    );
  }
}
