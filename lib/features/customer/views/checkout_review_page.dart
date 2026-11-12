import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../controllers/cart_controller.dart';
import '../controllers/checkout_controller.dart';
import '../services/customer_nav.dart';
import '../widgets/customer_widgets.dart';

/// Order review and confirmation (C-18).
class CheckoutReviewPage extends StatelessWidget {
  const CheckoutReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CheckoutController c = Get.find<CheckoutController>();
    final CartController cart = c.cart;
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('c_review_title'.tr)),
      body: Obx(() {
        if (cart.isEmpty) {
          return EmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'c_cart_empty'.tr,
            message: 'c_cart_empty_hint'.tr,
            actionLabel: 'c_back_home'.tr,
            onAction: CustomerNav.openHomeTab,
          );
        }
        final String? notice = c.notice.value;
        return Form(
          key: c.form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (cart.revalidating.value) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InlineNotice(
                    notice,
                    tone: NoticeTone.warning,
                    action: c.tooManyPending
                        ? AppButton(label: 'c_view_orders'.tr, expand: false, variant: AppButtonVariant.secondary, onPressed: CustomerNav.openOrdersTab)
                        : c.pharmacyInactive
                            ? AppButton(label: 'c_cart_clear'.tr, expand: false, variant: AppButtonVariant.secondary, onPressed: c.abandonCart)
                            : null,
                  ),
                ),
              SectionCard(
                title: cart.pharmacy.value?.name ?? '',
                icon: Icons.local_pharmacy_rounded,
                child: Column(
                  children: <Widget>[
                    for (final CartLine l in cart.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: Text('${l.medicine.displayName(isArabicNow())} × ${l.quantity}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            LtrText(Fmt.money(l.lineTotal, cart.currency), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    const Divider(height: 24),
                    InfoRow(label: 'c_total'.tr, value: Fmt.money(cart.total, cart.currency), ltr: true, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InlineNotice('c_hold_notice'.tr),
              const SizedBox(height: 8),
              InlineNotice('c_cash_notice'.tr),
              const SizedBox(height: 16),
              AppTextField(
                label: 'c_notes'.tr,
                hint: 'c_notes_hint'.tr,
                controller: c.notes,
                maxLines: 3,
                minLines: 2,
                maxLength: CheckoutController.notesMax,
                validator: Validators.length(max: CheckoutController.notesMax),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'c_contact_phone'.tr,
                helper: 'c_contact_phone_hint'.tr,
                controller: c.phone,
                ltr: true,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
                validator: Validators.optionalPhone,
              ),
              const SizedBox(height: 8),
              Text('c_review_footer'.tr, style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(() => BottomActionBar(
            child: AppButton(
              label: 'c_confirm_order'.tr,
              icon: Icons.check_rounded,
              loading: c.submitting.value,
              onPressed: cart.canCheckout && !cart.revalidating.value ? c.submitOrder : null,
            ),
          )),
    );
  }
}
