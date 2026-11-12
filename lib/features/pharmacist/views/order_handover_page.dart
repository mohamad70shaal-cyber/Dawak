import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/order.dart';
import '../controllers/order_handover_controller.dart';

/// Verify the order and hand the goods over (P-61, P-62).
class OrderHandoverPage extends StatelessWidget {
  const OrderHandoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final OrderHandoverController c = Get.find<OrderHandoverController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('p_handover_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => Obx(() {
          final Order? o = c.order.value;
          if (o == null) return const SizedBox.shrink();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: c.form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (c.notice.value != null) ...<Widget>[NoticeBanner(c.notice.value!), const SizedBox(height: 12)],
                  if (!c.canComplete) ...<Widget>[NoticeBanner('p_handover_not_ready'.tr, kind: NoticeKind.warning), const SizedBox(height: 12)],
                  SectionCard(
                    title: 'p_handover_check'.tr,
                    icon: Icons.fact_check_rounded,
                    child: Column(
                      children: <Widget>[
                        if (o.customerName.isNotEmpty) InfoRow(label: 'p_order_customer'.tr, value: o.customerName),
                        for (final OrderItem i in o.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: <Widget>[
                                Expanded(child: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 8),
                                LtrText('× ${i.quantity}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: <Widget>[
                        Text('p_handover_collect'.tr, style: t.titleSmall),
                        const SizedBox(height: 4),
                        LtrText(Fmt.money(o.subtotal, o.currency), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('p_handover_ask_code'.tr, style: t.bodyMedium),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: 'p_handover_code'.tr,
                    hint: 'DWK-XXXXXXXXXX',
                    controller: c.reference,
                    ltr: true,
                    enabled: c.canComplete,
                    prefixIcon: Icons.qr_code_2_rounded,
                    textInputAction: TextInputAction.done,
                    validator: c.referenceRule,
                    onSubmitted: (String _) => c.complete(),
                  ),
                  const SizedBox(height: 24),
                  Obx(() => AppButton(
                        label: 'p_handover_confirm'.tr,
                        icon: Icons.payments_rounded,
                        loading: c.submitting.value,
                        onPressed: c.canComplete ? c.complete : null,
                      )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
