import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import '../controllers/pharmacy_settings_controller.dart';

/// Settings tab (P-S0): the pharmacy, links to its screens, language, legal pages and sign-out.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  Widget _tile(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, textDirection: TextDirection.ltr),
        minVerticalPadding: 12,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Obx(() {
          final Pharmacy? ph = c.pharmacy.value;
          if (ph == null) return const SizedBox.shrink();
          final MemberRole? role = c.role;
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(ph.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(ph.fullAddress, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    ApprovalChip(ph.status),
                    if (role != null) StatusChip(label: 'member_${role.name}'.tr, color: AppColors.primary, icon: Icons.badge_outlined),
                    StatusChip(
                      label: ph.isListed ? 'p_settings_listed'.tr : 'p_settings_unlisted'.tr,
                      color: ph.isListed ? AppColors.success : AppColors.warning,
                      icon: ph.isListed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        _Group(title: 'p_settings_pharmacy'.tr, children: <Widget>[
          _tile(Icons.local_pharmacy_outlined, 'p_settings_profile'.tr, () => Get.toNamed<dynamic>(AppRoutes.settingsProfile)),
          _tile(Icons.place_outlined, 'p_settings_contact'.tr, () => Get.toNamed<dynamic>(AppRoutes.settingsContact)),
          _tile(Icons.my_location_rounded, 'p_settings_location'.tr, () => Get.toNamed<dynamic>(AppRoutes.settingsLocation)),
          _tile(Icons.schedule_rounded, 'p_settings_hours'.tr, () => Get.toNamed<dynamic>(AppRoutes.settingsHours)),
        ]),
        const SizedBox(height: 12),
        _Group(title: 'p_settings_records'.tr, children: <Widget>[
          _tile(Icons.receipt_long_outlined, 'p_sales_title'.tr, () => Get.toNamed<dynamic>(AppRoutes.salesHistory)),
          _tile(Icons.mark_chat_unread_outlined, 'p_req_inbox_title'.tr, () => Get.toNamed<dynamic>(AppRoutes.pharmacistRequests)),
        ]),
        const SizedBox(height: 12),
        _Group(title: 'p_settings_account'.tr, children: <Widget>[
          _tile(Icons.lock_outline_rounded, 'p_settings_security'.tr, () => Get.toNamed<dynamic>(AppRoutes.settingsSecurity), subtitle: c.email),
          Obx(() => _tile(
                Icons.translate_rounded,
                'language'.tr,
                c.toggleLanguage,
                subtitle: c.isArabic ? 'language_ar'.tr : 'language_en'.tr,
              )),
          _tile(Icons.privacy_tip_outlined, 'auth_privacy'.tr, () => Get.toNamed<dynamic>(AppRoutes.legalPrivacy)),
          _tile(Icons.description_outlined, 'auth_terms'.tr, () => Get.toNamed<dynamic>(AppRoutes.legalTerms)),
        ]),
        const SizedBox(height: 12),
        AppCard(
          onTap: () async {
            final bool ok = await confirmDialog(
              title: 'p_settings_signout_title'.tr,
              message: 'p_settings_signout_message'.tr,
              confirmLabel: 'auth_sign_out'.tr,
            );
            if (ok) await c.signOut();
          },
          child: Row(
            children: <Widget>[
              const Icon(Icons.logout_rounded, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(child: Text('auth_sign_out'.tr, style: t.titleSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700))),
            ],
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
          child: Text(title, style: t.labelLarge?.copyWith(color: context.palette.textSecondary)),
        ),
        AppCard(padding: EdgeInsets.zero, child: Column(children: children)),
      ],
    );
  }
}
