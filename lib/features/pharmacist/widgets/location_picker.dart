import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/map_links.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../data/models/geo.dart';
import '../controllers/shop_location_input.dart';

/// "Shop location" card: shows the chosen position and lets the pharmacist set it from the GPS or a pasted map link.
/// Customers see the distance to this position, so it has to be where the pharmacy really is.
class LocationPickerCard extends StatelessWidget {
  const LocationPickerCard({super.key, required this.input, this.readOnly = false, this.onChanged});

  final ShopLocationInput input;

  /// Managers and cashiers only look at the saved position.
  final bool readOnly;

  /// Called after a position was taken (GPS or paste).
  final VoidCallback? onChanged;

  Future<void> _openMap(GeoPoint p) async {
    try {
      final bool ok = await launchUrl(MapLinks.place(p), mode: LaunchMode.externalApplication);
      if (!ok) AppToast.error('p_loc_open_failed'.tr);
    } catch (_) {
      AppToast.error('p_loc_open_failed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return SectionCard(
      title: 'p_loc_title'.tr,
      icon: Icons.my_location_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('p_loc_intro'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
          Obx(() {
            final GeoPoint? point = input.point.value;
            if (point == null) {
              return StatusChip(label: 'p_loc_not_set'.tr, color: AppColors.warning, icon: Icons.location_off_outlined);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                StatusChip(label: 'p_loc_set'.tr, color: AppColors.success, icon: Icons.check_circle_rounded),
                const SizedBox(height: 8),
                LtrText(point.label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                TextButton.icon(
                  onPressed: () => _openMap(point),
                  icon: const Icon(Icons.map_outlined),
                  label: Text('p_loc_open_map'.tr),
                ),
              ],
            );
          }),
          if (!readOnly) ...<Widget>[
            const SizedBox(height: 8),
            Obx(() => AppButton(
                  label: 'p_loc_use_current'.tr,
                  icon: Icons.gps_fixed_rounded,
                  loading: input.locating.value,
                  onPressed: () async {
                    if (await input.useCurrent()) onChanged?.call();
                  },
                )),
            const SizedBox(height: 16),
            AppTextField(
              label: 'p_loc_paste_label'.tr,
              helper: 'p_loc_paste_hint'.tr,
              controller: input.paste,
              ltr: true,
              prefixIcon: Icons.link_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (input.usePasted()) onChanged?.call();
              },
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'p_loc_use_pasted'.tr,
              icon: Icons.check_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () {
                if (input.usePasted()) onChanged?.call();
              },
            ),
            Obx(() {
              final String? e = input.error.value;
              if (e == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    NoticeBanner(e),
                    if (input.needsSettings.value)
                      TextButton.icon(
                        onPressed: input.openSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text('p_loc_open_settings'.tr),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
