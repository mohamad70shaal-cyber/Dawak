import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/notice_banner.dart';
import '../controllers/order_find_controller.dart';

/// Find an order by the customer's code (P-60).
class OrderFindPage extends StatelessWidget {
  const OrderFindPage({super.key});

  @override
  Widget build(BuildContext context) {
    final OrderFindController c = Get.find<OrderFindController>();
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('p_find_title'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: c.form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('p_find_intro'.tr, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
              const SizedBox(height: 16),
              Obx(() => c.notice.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.notice.value!))),
              AppTextField(
                label: 'p_handover_code'.tr,
                hint: 'DWK-XXXXXXXXXX',
                controller: c.reference,
                ltr: true,
                autofocus: true,
                prefixIcon: Icons.qr_code_2_rounded,
                textInputAction: TextInputAction.search,
                validator: c.referenceRule,
                onSubmitted: (String _) => c.find(),
              ),
              const SizedBox(height: 24),
              Obx(() => AppButton(label: 'p_find_action'.tr, icon: Icons.search_rounded, loading: c.submitting.value, onPressed: c.find)),
            ],
          ),
        ),
      ),
    );
  }
}
