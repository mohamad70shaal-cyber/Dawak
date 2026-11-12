import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_details_controller.dart';
import '../widgets/customer_widgets.dart';

/// Medicine details (C-13).
class MedicineDetailsPage extends StatelessWidget {
  const MedicineDetailsPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final String targetId = id.isNotEmpty ? id : (Get.parameters['id'] ?? '');
    final MedicineDetailsController c = Get.isRegistered<MedicineDetailsController>(tag: targetId)
        ? Get.find<MedicineDetailsController>(tag: targetId)
        : Get.put<MedicineDetailsController>(MedicineDetailsController(targetId), tag: targetId);
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('c_medicine_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) {
          final Medicine? m = c.medicine.value;
          if (m == null) return const SizedBox.shrink();
          final bool ar = isArabicNow();
          final String second = m.secondaryName(ar);
          return RefreshIndicator(
            onRefresh: c.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(m.displayName(ar), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (second.isNotEmpty) Text(second, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
                      const SizedBox(height: 12),
                      if ((m.brandName ?? '').isNotEmpty) InfoRow(label: 'c_brand'.tr, value: m.brandName!),
                      if ((m.activeIngredient ?? '').isNotEmpty) InfoRow(label: 'c_active_ingredient'.tr, value: m.activeIngredient!),
                      if ((m.strength ?? '').isNotEmpty) InfoRow(label: 'c_strength'.tr, value: m.strength!, ltr: true),
                      if ((m.dosageForm ?? '').isNotEmpty) InfoRow(label: 'c_dosage_form'.tr, value: m.dosageForm!),
                      if ((m.packageDescription ?? '').isNotEmpty) InfoRow(label: 'c_package'.tr, value: m.packageDescription!),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InlineNotice('c_disclaimer'.tr),
                const SizedBox(height: 16),
                AppButton(
                  label: 'c_find_pharmacies'.tr,
                  icon: Icons.local_pharmacy_rounded,
                  onPressed: () => Get.toNamed<dynamic>(AppRoutes.medicineOffers(id)),
                ),
                const SizedBox(height: 12),
                Obx(() => AppButton(
                      label: 'c_ask_nearby'.tr,
                      icon: Icons.radar_rounded,
                      variant: AppButtonVariant.secondary,
                      loading: c.starting,
                      onPressed: c.askNearby,
                    )),
                const SizedBox(height: 6),
                Text('c_ask_nearby_hint'.tr, style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
                Obx(() {
                  final String? error = c.where.error.value;
                  if (error == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InlineNotice(
                      error,
                      tone: NoticeTone.warning,
                      action: c.where.needsSettings.value
                          ? AppButton(label: 'c_open_settings'.tr, icon: Icons.settings_rounded, variant: AppButtonVariant.secondary, expand: false, onPressed: c.where.openSettings)
                          : null,
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
