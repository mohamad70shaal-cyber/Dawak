import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/quantity_stepper.dart';
import '../../../core/widgets/states.dart';
import '../controllers/pos_controller.dart';

/// Confirm the cash sale (P-41): lines with quantities, discount (owners/managers), preview totals, confirm.
class PosCheckoutPage extends StatelessWidget {
  const PosCheckoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PosController c = Get.find<PosController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_pos_checkout_title'.tr)),
      body: Obx(() {
        if (c.isEmpty) {
          return EmptyState(
            icon: Icons.shopping_basket_outlined,
            title: 'p_pos_basket_empty'.tr,
            message: 'p_pos_basket_empty_hint'.tr,
            actionLabel: 'back'.tr,
            onAction: () => Get.back<dynamic>(),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (c.notice.value != null) ...<Widget>[NoticeBanner(c.notice.value!, kind: NoticeKind.warning), const SizedBox(height: 12)],
            for (final PosLine l in c.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: Text(l.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          IconButton(tooltip: 'remove'.tr, onPressed: () => c.remove(l.productId), icon: const Icon(Icons.delete_outline_rounded)),
                        ],
                      ),
                      if (l.spec.isNotEmpty) Text(l.spec, style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          QuantityStepper(value: l.quantity, min: 1, max: PosController.maxQtyPerLine, onChanged: (int v) => c.setQuantity(l.productId, v)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                LtrText('${Fmt.money(l.unitPrice, c.currency)} × ${l.quantity}', style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                                LtrText(Fmt.money(l.lineTotal, c.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (c.canDiscount) ...<Widget>[
              const SizedBox(height: 4),
              AppTextField(
                label: 'p_pos_discount'.tr,
                hint: 'p_pos_discount_hint'.tr,
                controller: c.discountInput,
                ltr: true,
                prefixIcon: Icons.percent_rounded,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: c.applyDiscount,
              ),
              if (c.discountError.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(c.discountError.value!, style: t.bodySmall?.copyWith(color: AppColors.error)),
                ),
              const SizedBox(height: 12),
            ],
            SectionCard(
              title: 'p_pos_totals'.tr,
              icon: Icons.receipt_long_rounded,
              child: Column(
                children: <Widget>[
                  InfoRow(label: 'p_receipt_subtotal'.tr, value: Fmt.money(c.subtotal, c.currency), ltr: true),
                  if (c.discount.value > 0) InfoRow(label: 'p_receipt_discount'.tr, value: '-${Fmt.money(c.discount.value, c.currency)}', ltr: true),
                  InfoRow(label: 'p_receipt_grand_total'.tr, value: Fmt.money(c.total, c.currency), ltr: true, bold: true),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('p_pos_cash_note'.tr, style: t.bodySmall?.copyWith(color: pal.textSecondary)),
          ],
        );
      }),
      bottomNavigationBar: Obx(() => c.isEmpty
          ? const SizedBox.shrink()
          : BottomActionBar(
              child: AppButton(
                label: 'p_pos_confirm'.trParams(<String, String>{'total': Fmt.money(c.total, c.currency)}),
                icon: Icons.payments_rounded,
                loading: c.submitting.value,
                onPressed: c.checkout,
              ),
            )),
    );
  }
}
