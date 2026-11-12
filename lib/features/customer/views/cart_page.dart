import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/quantity_stepper.dart';
import '../../../core/widgets/states.dart';
import '../controllers/cart_controller.dart';
import '../customer_tabs.dart';
import '../widgets/customer_widgets.dart';

/// Cart (C-17): one pharmacy, at most [CartController.maxQtyPerLine] of each medicine. Sending it asks the pharmacy to
/// hold the medicines; nothing is paid in the app.
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CartController c = Get.find<CartController>();
    return Obx(() {
      if (c.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: Text('c_cart_title'.tr)),
          body: EmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'c_cart_empty'.tr,
            message: 'c_cart_empty_hint'.tr,
            actionLabel: 'c_start_searching'.tr,
            onAction: () => CustomerTabs.go(CustomerTabs.search),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text('c_cart_title'.tr),
          actions: <Widget>[
            IconButton(
              tooltip: 'c_cart_clear'.tr,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final bool ok = await confirmDialog(
                  title: 'c_cart_clear'.tr,
                  message: 'c_cart_clear_message'.tr,
                  confirmLabel: 'c_cart_clear'.tr,
                  destructive: true,
                );
                if (ok) c.clear();
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await c.revalidate();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (c.revalidating.value) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
              Text(c.pharmacy.value?.name ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (c.syncFailed.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InlineNotice(
                    'c_notice_sync_failed'.tr,
                    tone: NoticeTone.warning,
                    action: AppButton(label: 'retry'.tr, expand: false, variant: AppButtonVariant.secondary, onPressed: c.revalidate),
                  ),
                ),
              if (c.lastSync.value?.hasChanges ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InlineNotice(_syncText(c.lastSync.value!), tone: NoticeTone.warning),
                ),
              for (final CartLine l in c.lines)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _CartLineCard(cart: c, line: l)),
              InlineNotice('c_hold_notice'.tr),
              const SizedBox(height: 8),
              InlineNotice('c_cash_notice'.tr),
            ],
          ),
        ),
        bottomNavigationBar: BottomActionBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('c_total'.tr, style: Theme.of(context).textTheme.titleMedium)),
                  LtrText(Fmt.money(c.total, c.currency), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'c_continue_checkout'.tr,
                icon: Icons.arrow_forward_rounded,
                onPressed: c.canCheckout ? () => Get.toNamed<dynamic>(AppRoutes.checkoutReview) : null,
              ),
            ],
          ),
        ),
      );
    });
  }

  static String _syncText(CartSyncResult r) {
    if (r.unavailable > 0) return 'c_notice_unavailable'.tr;
    return 'c_notice_price_changed'.tr;
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({required this.cart, required this.line});

  final CartController cart;
  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(line.medicine.displayName(isArabicNow()), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (line.medicine.specLine.isNotEmpty)
                      Text(line.medicine.specLine, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    LtrText('${Fmt.money(line.unitPrice, cart.currency)} × ${line.quantity}', style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: 6),
                    FreshnessChip(line.freshness, confirmedAt: line.confirmedAt),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'remove'.tr,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => cart.remove(line.productId),
              ),
            ],
          ),
          if (line.unavailable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineNotice('c_line_unavailable'.tr, tone: NoticeTone.error),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              QuantityStepper(
                value: line.quantity,
                max: CartController.maxQtyPerLine,
                enabled: !line.unavailable,
                onChanged: (int q) => cart.setQuantity(line.productId, q),
              ),
              const SizedBox(width: 12),
              Expanded(child: LtrText(Fmt.money(line.lineTotal, cart.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          if (line.quantity >= CartController.maxQtyPerLine && !line.unavailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'c_max_per_order'.trParams(<String, String>{'n': '${CartController.maxQtyPerLine}'}),
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
