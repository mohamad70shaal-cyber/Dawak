import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../controllers/order_details_controller.dart';
import '../widgets/customer_widgets.dart';

/// Cancel order (C-23): states the consequence, asks for an optional reason, then cancels on the server.
class OrderCancelPage extends StatelessWidget {
  const OrderCancelPage({super.key, required this.id});

  final String id;

  Future<void> _cancel(OrderDetailsController c) async {
    final String? reason = await reasonDialog(
      title: 'c_cancel_dialog_title'.tr,
      label: 'c_cancel_reason_label'.tr,
      message: 'c_cancel_consequence'.tr,
      confirmLabel: 'c_cancel_confirm'.tr,
      minLength: 0,
    );
    if (reason == null) return;
    final bool ok = await c.cancel(reason: reason);
    if (ok) {
      AppToast.success('c_order_cancelled'.tr);
      Get.back<dynamic>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrderDetailsController c = Get.find<OrderDetailsController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('c_cancel_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) => Obx(() {
          final Order? o = c.order.value;
          if (o == null) return const SizedBox.shrink();
          final bool held = o.status == OrderStatus.accepted || o.status == OrderStatus.readyForPickup;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LtrText(o.publicRef, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(o.pharmacyName),
                    const SizedBox(height: 8),
                    OrderStatusChip(o.status),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!c.canCancel)
                InlineNotice('c_cannot_cancel'.tr, tone: NoticeTone.warning)
              else ...<Widget>[
                InlineNotice(held ? 'c_cancel_consequence_held'.tr : 'c_cancel_consequence'.tr, tone: NoticeTone.warning),
                const SizedBox(height: 16),
                AppButton(
                  label: 'c_cancel_order'.tr,
                  icon: Icons.cancel_outlined,
                  variant: AppButtonVariant.danger,
                  loading: c.submitting.value,
                  onPressed: () => _cancel(c),
                ),
              ],
              const SizedBox(height: 8),
              AppButton(label: 'c_keep_order'.tr, variant: AppButtonVariant.secondary, onPressed: () => Get.back<dynamic>()),
            ],
          );
        }),
      ),
    );
  }
}
