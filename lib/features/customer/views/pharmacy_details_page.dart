import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/pharmacy.dart';
import '../controllers/cart_controller.dart';
import '../controllers/pharmacy_details_controller.dart';
import '../widgets/cart_actions.dart';
import '../widgets/customer_launch.dart';
import '../widgets/customer_widgets.dart';

/// Public pharmacy page (C-15): details, the medicines it says it has (with when it last confirmed them) and add to cart.
class PharmacyDetailsPage extends StatelessWidget {
  const PharmacyDetailsPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final PharmacyDetailsController c = Get.find<PharmacyDetailsController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Obx(() => Text(c.pharmacy.value?.name ?? 'c_pharmacy_title'.tr))),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) {
          final PublicPharmacy? ph = c.pharmacy.value;
          if (ph == null) return const SizedBox.shrink();
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.place_outlined, size: 20, color: p.primaryText),
                          const SizedBox(width: 8),
                          Expanded(child: Text(ph.fullAddress, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          AppButton(
                            label: 'c_pharmacy_contact'.tr,
                            icon: Icons.contact_phone_outlined,
                            variant: AppButtonVariant.secondary,
                            expand: false,
                            onPressed: () => Get.toNamed<dynamic>(AppRoutes.pharmacyContactOf(id)),
                          ),
                          if (ph.location != null)
                            AppButton(
                              label: 'c_directions_btn'.tr,
                              icon: Icons.directions_rounded,
                              variant: AppButtonVariant.secondary,
                              expand: false,
                              onPressed: () => openDirections(ph.location!),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: InlineNotice('c_availability_note'.tr),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchField(hint: 'c_catalogue_search'.tr, onChanged: c.search, onSubmitted: c.search),
              ),
              Expanded(
                child: PagedListView<PublicProduct>(
                  paged: c.catalogue,
                  empty: EmptyState(icon: Icons.medication_outlined, title: 'c_catalogue_empty'.tr, message: 'c_catalogue_empty_hint'.tr),
                  itemBuilder: (BuildContext context, PublicProduct pr) => _ProductCard(controller: c, product: pr),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Obx(() {
        if (!c.cartIsHere) return const SizedBox.shrink();
        final CartController cart = c.cart;
        return BottomActionBar(
          child: AppButton(
            label: 'c_view_cart_total'.trParams(<String, String>{'n': '${cart.itemCount}', 'total': Fmt.money(cart.total, cart.currency)}),
            icon: Icons.shopping_cart_rounded,
            onPressed: () => Get.toNamed<dynamic>(AppRoutes.cart),
          ),
        );
      }),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.controller, required this.product});

  final PharmacyDetailsController controller;
  final PublicProduct product;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final bool ar = isArabicNow();
    final Medicine m = product.medicine;
    final bool highlighted = controller.highlightMedicineId != null && controller.highlightMedicineId == m.id;
    return AppCard(
      color: highlighted ? p.softPrimary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(m.displayName(ar), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              LtrText(Fmt.money(product.price, product.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          if (m.specLine.isNotEmpty) Text(m.specLine, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('c_searched_medicine'.tr, style: t.labelMedium?.copyWith(color: p.primaryText, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 8),
          FreshnessChip(product.freshness, confirmedAt: product.confirmedAt),
          const SizedBox(height: 8),
          Obx(() {
            final CartLine? line = controller.cart.lineFor(product.productId);
            return Row(
              children: <Widget>[
                Expanded(
                  child: line == null
                      ? const SizedBox.shrink()
                      : Text('c_in_cart'.trParams(<String, String>{'n': '${line.quantity}'}), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                AppButton(
                  label: 'c_add_to_cart'.tr,
                  icon: Icons.add_shopping_cart_rounded,
                  expand: false,
                  onPressed: () => addProductWithPrompt(controller, product),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
