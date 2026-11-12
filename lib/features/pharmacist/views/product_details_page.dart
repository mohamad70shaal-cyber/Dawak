import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/product_details_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// Product details (P-24).
class ProductDetailsPage extends StatelessWidget {
  const ProductDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProductDetailsController c = Get.find<ProductDetailsController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_product_details'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() {
            final PharmacyProduct? p = c.product.value;
            if (p == null) return const SizedBox.shrink();
            return _Body(c: c, p: p);
          }),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c, required this.p});

  final ProductDetailsController c;
  final PharmacyProduct p;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    final String currency = c.currency;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MedicineTitle(p.medicine, big: true),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  if (p.isAvailable)
                    FreshnessChip(p.freshness(), confirmedAt: p.confirmedAt)
                  else
                    StatusChip(label: 'p_state_unavailable'.tr, color: AppColors.textSecondary, icon: Icons.remove_circle_outline_rounded),
                ],
              ),
              if (!p.isAvailable) ...<Widget>[
                const SizedBox(height: 12),
                NoticeBanner('p_product_unavailable_hint'.tr, kind: NoticeKind.warning),
              ] else if (p.isStale()) ...<Widget>[
                const SizedBox(height: 12),
                NoticeBanner('p_product_stale_hint'.tr, kind: NoticeKind.warning),
              ],
              const SizedBox(height: 8),
              if ((p.medicine.activeIngredient ?? '').isNotEmpty) InfoRow(label: 'p_med_ingredient'.tr, value: p.medicine.activeIngredient!),
              if ((p.medicine.brandName ?? '').isNotEmpty) InfoRow(label: 'p_med_brand'.tr, value: p.medicine.brandName!),
              InfoRow(label: 'p_product_price'.tr, value: Fmt.money(p.price, currency), ltr: true, bold: true),
              InfoRow(label: 'p_product_confirmed'.tr, value: p.confirmedAt == null ? '—' : '${Fmt.dateTime(p.confirmedAt)} (${Fmt.ago(p.confirmedAt)})'),
            ],
          ),
        ),
        if (c.canManage) ...<Widget>[
          const SizedBox(height: 12),
          Obx(() => AppButton(
                label: 'p_product_confirm_action'.tr,
                icon: Icons.fact_check_outlined,
                loading: c.submitting.value,
                onPressed: c.confirmStillCorrect,
              )),
          const SizedBox(height: 8),
          AppButton(label: 'p_product_edit'.tr, icon: Icons.edit_rounded, variant: AppButtonVariant.secondary, onPressed: c.openEdit),
          const SizedBox(height: 8),
          Obx(() => AppButton(
                label: p.isAvailable ? 'p_product_mark_unavailable'.tr : 'p_product_mark_available'.tr,
                icon: p.isAvailable ? Icons.remove_circle_outline_rounded : Icons.check_circle_outline_rounded,
                variant: p.isAvailable ? AppButtonVariant.danger : AppButtonVariant.secondary,
                loading: c.submitting.value,
                onPressed: () => c.setAvailable(!p.isAvailable),
              )),
          const SizedBox(height: 16),
          Text('p_product_list_note'.tr, style: t.bodySmall?.copyWith(color: pal.textSecondary)),
        ],
      ],
    );
  }
}
