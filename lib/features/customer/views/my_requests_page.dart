import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/availability.dart';
import '../controllers/my_requests_controller.dart';
import '../widgets/customer_widgets.dart';

/// "My requests" (C-30): what the customer asked the pharmacies nearby, newest first.
class MyRequestsPage extends StatelessWidget {
  const MyRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MyRequestsController c = Get.find<MyRequestsController>();
    return Scaffold(
      appBar: AppBar(title: Text('c_requests_title'.tr)),
      body: PagedListView<AvailabilityRequestSummary>(
        paged: c.paged,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InlineNotice('c_requests_hint'.tr),
        ),
        empty: EmptyState(
          icon: Icons.radar_rounded,
          title: 'c_requests_empty_title'.tr,
          message: 'c_requests_empty_message'.tr,
        ),
        itemBuilder: (BuildContext context, AvailabilityRequestSummary s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RequestTile(
            request: s,
            onTap: () async {
              await Get.toNamed<dynamic>(AppRoutes.customerRequest(s.id));
              c.refreshList();
            },
          ),
        ),
      ),
    );
  }
}
