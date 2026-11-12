import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/quantity_stepper.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// Point of sale tab (P-34): search the pharmacy's list, add to the basket, change quantities; the bar at the bottom opens checkout.
class PosTab extends StatelessWidget {
  const PosTab({super.key});

  static void add(PosController c, PharmacyProduct p) {
    switch (c.add(p)) {
      case PosAdd.added:
        break;
      case PosAdd.atLimit:
        AppToast.info('p_pos_max_reached'.tr);
      case PosAdd.basketFull:
        AppToast.info('p_pos_basket_full'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PosController c = Get.find<PosController>();
    return Scaffold(
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(hint: 'p_pos_search_hint'.tr, onChanged: c.search, onSubmitted: c.search),
          ),
          Obx(() {
            final String? n = c.notice.value;
            return n == null
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _Notice(n));
          }),
          Expanded(
            child: PagedListView<PharmacyProduct>(
              paged: c.products,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              empty: EmptyState(icon: Icons.point_of_sale_rounded, title: 'p_pos_empty'.tr, message: 'p_pos_empty_hint'.tr),
              itemBuilder: (BuildContext context, PharmacyProduct p) => _ProductRow(c: c, p: p),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Obx(() {
        if (c.isEmpty) return const SizedBox.shrink();
        return _BasketBar(c: c);
      }),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tint(AppColors.warning),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.c, required this.p});

  final PosController c;
  final PharmacyProduct p;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MedicineTitle(p.medicine),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      LtrText(Fmt.money(p.price, c.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      if (!p.isAvailable) ...<Widget>[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text('p_pos_marked_unavailable'.tr,
                              style: t.bodySmall?.copyWith(color: pal.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Obx(() {
              final int q = c.qtyOf(p.id);
              if (q == 0) {
                return IconButton.filled(
                  tooltip: 'p_pos_add'.tr,
                  onPressed: () => PosTab.add(c, p),
                  icon: const Icon(Icons.add_rounded),
                );
              }
              return QuantityStepper(
                value: q,
                min: 0,
                max: PosController.maxQtyPerLine,
                onChanged: (int v) => c.setQuantity(p.id, v),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BasketBar extends StatelessWidget {
  const _BasketBar({required this.c});

  final PosController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return BottomActionBar(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('p_pos_basket_items'.trParams(<String, String>{'n': '${c.itemCount}'}), style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                LtrText(Fmt.money(c.subtotal, c.currency), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: AppButton(
              label: 'p_pos_review'.tr,
              icon: Icons.shopping_cart_checkout_rounded,
              expand: false,
              onPressed: () => Get.toNamed<dynamic>(AppRoutes.posCheckout),
            ),
          ),
        ],
      ),
    );
  }
}
