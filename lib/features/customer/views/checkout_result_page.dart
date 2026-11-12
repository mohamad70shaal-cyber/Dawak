import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/order.dart';
import '../controllers/cart_controller.dart';
import '../services/customer_nav.dart';
import '../widgets/customer_launch.dart';
import '../widgets/customer_widgets.dart';

/// Order submission result (C-19). The checkout screens are gone from the stack, so back can never resubmit.
class CheckoutResultPage extends StatelessWidget {
  const CheckoutResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CartController cart = Get.find<CartController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) CustomerNav.openOrdersTab();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('c_result_title'.tr), automaticallyImplyLeading: false),
        body: Obx(() {
          final Order? o = cart.lastPlaced.value;
          if (o == null) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'c_result_missing'.tr,
              message: 'c_result_missing_hint'.tr,
              actionLabel: 'c_view_orders'.tr,
              onAction: CustomerNav.openOrdersTab,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const SizedBox(height: 12),
              const Icon(Icons.check_circle_rounded, size: 72, color: AppColors.success),
              const SizedBox(height: 12),
              Text('c_order_sent_title'.tr, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('c_order_sent_message'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              AppCard(
                child: Column(
                  children: <Widget>[
                    Text('c_order_ref'.tr, style: t.labelLarge?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: LtrText(o.publicRef, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 8),
                    AppButton(label: 'copy'.tr, icon: Icons.copy_rounded, expand: false, variant: AppButtonVariant.secondary, onPressed: () => copyText(o.publicRef)),
                    const Divider(height: 24),
                    InfoRow(label: 'c_pharmacy'.tr, value: o.pharmacyName),
                    InfoRow(label: 'c_total'.tr, value: Fmt.money(o.subtotal, o.currency), ltr: true, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InlineNotice('c_show_code_notice'.tr),
              const SizedBox(height: 20),
              AppButton(label: 'c_view_order'.tr, icon: Icons.receipt_long_rounded, onPressed: () => CustomerNav.openOrder(o.id)),
              const SizedBox(height: 8),
              AppButton(label: 'c_back_home'.tr, variant: AppButtonVariant.secondary, onPressed: CustomerNav.openHomeTab),
            ],
          );
        }),
      ),
    );
  }
}
